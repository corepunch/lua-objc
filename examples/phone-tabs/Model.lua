local Model = {}

Model.recents = {
	{ title = "Weekly team standup", subtitle = "Monday 9:00 AM", systemImage = "person.3" },
	{ title = "Design review", subtitle = "Tuesday 2:00 PM", systemImage = "paintbrush" },
	{ title = "Release planning", subtitle = "Wednesday 11:00 AM", systemImage = "rosette" },
	{ title = "1:1 with manager", subtitle = "Thursday 3:30 PM", systemImage = "person.crop.circle" },
}

Model.favorites = {
	{ title = "Recipes", systemImage = "fork.knife" },
	{ title = "Travel", systemImage = "airplane" },
	{ title = "Books", systemImage = "book" },
	{ title = "Workouts", systemImage = "dumbbell" },
	{ title = "Music", systemImage = "music.note" },
}

Model.profile = {
	name = "Alex Johnson",
	email = "alex@example.com",
	files = 12,
	storage = "2.4 GB of 5 GB",
}

return Model
