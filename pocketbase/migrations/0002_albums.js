/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const collection = new Collection({
    name: "albums",
    type: "base",
    listRule: "",
    viewRule: "",
    createRule: "",
    updateRule: "",
    deleteRule: "",
    fields: [
      // app-encrypted envelope: name, cover ref, order
      { name: "cipher_meta", type: "json" },
      { name: "modified_at", type: "number" },
      { name: "deleted", type: "bool" },
    ],
  });

  return app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("albums");
  return app.delete(collection);
});
