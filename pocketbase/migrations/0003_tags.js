/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const collection = new Collection({
    name: "tags",
    type: "base",
    listRule: "",
    viewRule: "",
    createRule: "",
    updateRule: "",
    deleteRule: "",
    fields: [
      // app-encrypted tag name (single secret field, no envelope needed)
      { name: "cipher_name", type: "text", required: true },
      { name: "modified_at", type: "number" },
      { name: "deleted", type: "bool" },
    ],
  });

  return app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("tags");
  return app.delete(collection);
});
