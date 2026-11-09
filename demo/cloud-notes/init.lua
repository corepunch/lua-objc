-- Notes kept online in Appwrite (docs/backend.md): the first app on remote
-- models. Its <Backend> names no project, so it saves to the person's own
-- project connected on the device (scripts/appwrite/connect.lua) and creates
-- its table there at launch; the person is anonymous until they register on
-- the Account page.
return require("data.app").launcher("demo/cloud-notes/app.xml")
