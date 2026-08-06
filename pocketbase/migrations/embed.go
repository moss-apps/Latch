package migrations

import "embed"

// Migrations bundles the JS schema migrations into the binary so the Android
// sidecar is self-contained (no sibling files next to the .so).
//
//go:embed *.js
var FS embed.FS
