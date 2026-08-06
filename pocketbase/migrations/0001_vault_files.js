/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  // ponytail: listRule/viewRule/createRule/updateRule/deleteRule = "" (public)
  // because the loopback binary gates every request with a random auth token
  // at the HTTP layer; PB-level rules would only block our own token-bearing
  // client (there are no PB user accounts in the embedded role).
  const collection = new Collection({
    name: "vault_files",
    type: "base",
    listRule: "",
    viewRule: "",
    createRule: "",
    updateRule: "",
    deleteRule: "",
    fields: [
      // on-disk shard path / content hash; non-secret, used for sync + lookup
      { name: "blob_ref", type: "text", required: true },
      // app-encrypted envelope: tags, albumIds, folderId, originalName, dates
      { name: "cipher_meta", type: "json" },
      // plaintext epoch millis, kept sortable (non-secret)
      { name: "modified_at", type: "number" },
      // tombstone
      { name: "deleted", type: "bool" },
    ],
  });

  return app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("vault_files");
  return app.delete(collection);
});
