-- Our shared Appwrite project for development (docs/backend.md): prototypes,
-- demos and Lua Studio. An app's `<Backend provider="appwrite" />` with no
-- `project` uses it. Shipping builds refuse it and need the app's own project:
-- its end-user accounts are shared by every app that uses it.
--
-- The project is "LuaStudio" on Appwrite Cloud, Frankfurt.
return {
	endpoint = "https://fra.cloud.appwrite.io/v1",
	project = "6af0e3d0002aa438b655",
}
