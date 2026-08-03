local Model = {}

Model.employees = {
	{ _id = "1", name = "Alice Chen",    role = "Engineer",   dept = "Core" },
	{ _id = "2", name = "Bob Martinez",  role = "Designer",   dept = "UX" },
	{ _id = "3", name = "Carol Park",    role = "Manager",    dept = "Eng" },
	{ _id = "4", name = "Dave Johnson",  role = "Engineer",   dept = "Core" },
	{ _id = "5", name = "Eve Williams",  role = "Analyst",    dept = "Data" },
	{ _id = "6", name = "Frank Brown",   role = "Intern",     dept = "Eng" },
}

function Model.find(id)
	for _, emp in ipairs(Model.employees) do
		if emp._id == id then return emp end
	end
end

return Model
