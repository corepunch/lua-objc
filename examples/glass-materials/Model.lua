local Model = {}

function Model.new()
    return {
        materials = {
            { name = "Ultra Thin", value = "ultraThin" },
            { name = "Thin", value = "thin" },
            { name = "Regular", value = "regular" },
            { name = "Thick", value = "thick" },
            { name = "Ultra Thick", value = "ultraThick" },
        },
        selectedMaterial = "regular",
        isMinimizedOnScroll = true,
    }
end

return Model
