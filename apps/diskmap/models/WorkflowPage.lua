-- One class for the pages of every kind of work: each is built for its own id.
return require("apps.diskmap.models.ListPage").class(function(services, id)
	return require("apps.diskmap.models.Workflow").page(services, services.entry(id))
end)
