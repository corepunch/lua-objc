-- A small notebook: folders, notes with tags and a body of paragraphs and
-- checklist items, which note is selected and what the search matches.
-- Sample data only; nothing is saved.
local Model = {}
Model.__index = Model

Model.FOLDERS = {
	{id = "all", name = "All Notes", icon = "note.text", color = "systemYellow"},
	{id = "work", name = "Work", icon = "briefcase.fill", color = "systemBlue"},
	{id = "ideas", name = "Ideas", icon = "lightbulb.fill", color = "systemOrange"},
	{id = "personal", name = "Personal", icon = "person.fill", color = "systemGreen"},
	{id = "recipes", name = "Recipes", icon = "fork.knife", color = "systemPink"},
}

Model.NOTES = {
	{id = 1, folder = "work", title = "Launch plan", date = "9:41", favorite = true, tags = {"launch", "q4"},
		body = {
			{kind = "heading", text = "Goals"},
			{kind = "text", text = "Ship the new onboarding on every platform in one release. The Mac, iPad and iPhone apps share the same Lua and XML, so a change lands everywhere at once."},
			{kind = "check", text = "Final pass on the welcome screens", done = true},
			{kind = "check", text = "Record the promo reel", done = true},
			{kind = "check", text = "Localise the App Store copy"},
			{kind = "check", text = "Press kit to partners"},
			{kind = "heading", text = "Timeline"},
			{kind = "text", text = "Code freeze on the 12th, review build on the 15th, launch on the 20th at 10:00 Pacific."},
			{kind = "quote", text = "Make the first minute feel effortless."},
		}},
	{id = 2, folder = "ideas", title = "Widget concepts", date = "Yesterday", favorite = true, tags = {"design"},
		body = {{kind = "text", text = "A glanceable progress ring for the Lock Screen, and a medium widget that shows the next three tasks."}}},
	{id = 3, folder = "personal", title = "Weekend in Lisbon", date = "Yesterday", tags = {"travel"},
		body = {{kind = "text", text = "Tram 28 early, pastéis in Belém, sunset at the Miradouro da Senhora do Monte."}}},
	{id = 4, folder = "recipes", title = "Miso glazed aubergine", date = "Monday", favorite = true, tags = {"dinner"},
		body = {{kind = "text", text = "White miso, mirin, a little sugar. Score the flesh deeply and grill until it collapses."}}},
	{id = 5, folder = "work", title = "Interview questions", date = "Sunday", tags = {"hiring"},
		body = {{kind = "text", text = "Walk me through a bug you were proud to fix. What would you cut from our app?"}}},
	{id = 6, folder = "ideas", title = "Podcast outline", date = "Friday", tags = {"audio"},
		body = {{kind = "text", text = "Episode one: why native still matters. Guests from three indie studios."}}},
	{id = 7, folder = "personal", title = "Books to read", date = "12 Sep", tags = {"reading"},
		body = {{kind = "text", text = "The Timeless Way of Building, Piranesi, The Dispossessed."}}},
}

function Model.new(notes)
	local self = setmetatable({notes = notes or Model.NOTES, selected = 1, query = ""}, Model)
	return self
end

function Model:find(id)
	for _, note in ipairs(self.notes) do if note.id == id then return note end end
end

function Model:select(id)
	if self:find(id) then self.selected = id end
end

function Model:search(query)
	self.query = query or ""
end

local function matches(note, query)
	if query == "" then return true end
	query = query:lower()
	if note.title:lower():find(query, 1, true) then return true end
	for _, block in ipairs(note.body) do
		if block.text:lower():find(query, 1, true) then return true end
	end
	return false
end

local function snippet(note)
	for _, block in ipairs(note.body) do
		if block.kind == "text" then return block.text end
	end
	return ""
end

-- The notes the search matches, as the list shows them.
function Model:visible()
	local rows = {}
	for _, note in ipairs(self.notes) do
		if matches(note, self.query) then
			table.insert(rows, {id = note.id, title = note.title, date = note.date, snippet = snippet(note),
				favorite = note.favorite == true})
		end
	end
	return rows
end

function Model:favorites()
	local rows = {}
	for _, row in ipairs(self:visible()) do if row.favorite then table.insert(rows, row) end end
	return rows
end

-- The sidebar's folders with their note counts.
function Model:folders()
	local counts = {all = #self.notes}
	for _, note in ipairs(self.notes) do counts[note.folder] = (counts[note.folder] or 0) + 1 end
	local rows = {{section = true, title = "iCloud"}}
	for _, folder in ipairs(Model.FOLDERS) do
		table.insert(rows, {id = folder.id, name = folder.name, icon = folder.icon, color = folder.color,
			badge = tostring(counts[folder.id] or 0)})
	end
	return rows
end

-- The selected note for the detail pane.
function Model:note()
	local note = self:find(self.selected)
	if not note then return nil end
	local folder
	for _, f in ipairs(Model.FOLDERS) do if f.id == note.folder then folder = f end end
	return {id = note.id, title = note.title, date = note.date, tags = note.tags, body = note.body,
		folder = folder.name, color = folder.color, favorite = note.favorite == true}
end

return Model
