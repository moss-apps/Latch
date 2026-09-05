package webui

import (
	"bytes"
	"container/list"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/jpeg"
	"sync"

	_ "image/gif"
	_ "image/png"

	xdraw "golang.org/x/image/draw"

	_ "golang.org/x/image/webp" // decode-only, all thumbs need
)

const (
	thumbMaxSide  = 320
	thumbQuality  = 75
	thumbCacheMax = 300
	thumbBytesMax = 48 << 20
	thumbMaxPix   = 80_000_000
)

// thumbCache holds decrypted thumbnails in memory only — never on disk —
// and dies with the session (dropUnlock clears it).
type thumbCache struct {
	mu    sync.Mutex
	order *list.List // front = most recent
	items map[string]*list.Element
	bytes int
}

type thumbItem struct {
	key string
	jpg []byte
}

func newThumbCache() *thumbCache {
	return &thumbCache{order: list.New(), items: map[string]*list.Element{}}
}

func (c *thumbCache) get(key string) []byte {
	c.mu.Lock()
	defer c.mu.Unlock()
	el, ok := c.items[key]
	if !ok {
		return nil
	}
	c.order.MoveToFront(el)
	return el.Value.(*thumbItem).jpg
}

func (c *thumbCache) put(key string, jpg []byte) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if el, ok := c.items[key]; ok {
		c.bytes -= len(el.Value.(*thumbItem).jpg)
		c.order.Remove(el)
		delete(c.items, key)
	}
	c.items[key] = c.order.PushFront(&thumbItem{key, jpg})
	c.bytes += len(jpg)
	for c.bytes > thumbBytesMax || len(c.items) > thumbCacheMax {
		last := c.order.Back()
		if last == nil {
			break
		}
		t := last.Value.(*thumbItem)
		c.bytes -= len(t.jpg)
		c.order.Remove(last)
		delete(c.items, t.key)
	}
}

func (c *thumbCache) clear() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.items = map[string]*list.Element{}
	c.order.Init()
	c.bytes = 0
}

// makeThumbnail decodes plaintext image bytes and re-encodes a ≤320px jpeg
// on a white matte (jpeg has no alpha).
func makeThumbnail(pt []byte) ([]byte, error) {
	cfg, _, err := image.DecodeConfig(bytes.NewReader(pt))
	if err != nil {
		return nil, err
	}
	if cfg.Width <= 0 || cfg.Height <= 0 || cfg.Width*cfg.Height > thumbMaxPix {
		return nil, fmt.Errorf("image too large to thumbnail (%dx%d)", cfg.Width, cfg.Height)
	}
	img, _, err := image.Decode(bytes.NewReader(pt))
	if err != nil {
		return nil, err
	}
	b := img.Bounds()
	tw, th := b.Dx(), b.Dy()
	if side := max(tw, th); side > thumbMaxSide {
		scale := float64(thumbMaxSide) / float64(side)
		tw = max(1, int(float64(tw)*scale+0.5))
		th = max(1, int(float64(th)*scale+0.5))
	}
	dst := image.NewRGBA(image.Rect(0, 0, tw, th))
	draw.Draw(dst, dst.Bounds(), &image.Uniform{C: color.White}, image.Point{}, draw.Src)
	xdraw.CatmullRom.Scale(dst, dst.Bounds(), img, b, xdraw.Over, nil)
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, dst, &jpeg.Options{Quality: thumbQuality}); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}
