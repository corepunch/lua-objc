local Model = {}

Model.recents = {
	{ title = "Weekly team standup", subtitle = "Monday 9:00 AM", systemImage = "person.3" },
	{ title = "Design review", subtitle = "Tuesday 2:00 PM", systemImage = "paintbrush" },
	{ title = "Release planning", subtitle = "Wednesday 11:00 AM", systemImage = "rosette" },
	{ title = "1:1 with manager", subtitle = "Thursday 3:30 PM", systemImage = "person.crop.circle" },
}

Model.featured = {
	title = "A slower way to move",
	subtitle = "Notes from the mountain trail",
	image = "demo/phone-tabs/assets/home-mountain.jpg",
}

Model.favorites = {
	{ title = "Lake escape", subtitle = "Travel inspiration", image = "demo/phone-tabs/assets/favorite-lake.jpg" },
	{ title = "Good companions", subtitle = "Weekend ideas", image = "demo/phone-tabs/assets/favorite-dog.jpg" },
	{ title = "Into the trees", subtitle = "Places to explore", image = "demo/phone-tabs/assets/favorite-forest.jpg" },
}

Model.profile = {
	name = "Alex Johnson",
	email = "alex@example.com",
	files = 12,
	storage = "2.4 GB of 5 GB",
	cover = "demo/phone-tabs/assets/profile-cover.jpg",
	avatar = "demo/phone-tabs/assets/profile-avatar.jpg",
}

return Model
