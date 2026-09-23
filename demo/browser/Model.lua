local Model = {}

function Model.new()
    return {
        -- Predefined URLs for easy testing
        favoriteURLs = {
            { title = "Claude", url = "https://claude.ai" },
            { title = "GitHub", url = "https://github.com" },
            { title = "Example", url = "https://example.com" },
            { title = "Apple", url = "https://apple.com" },
        },
        homepageURL = "https://example.com",
    }
end

return Model
