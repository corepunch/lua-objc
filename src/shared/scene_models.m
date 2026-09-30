#pragma mark - SceneKit model files

/* Model files for SceneKit scenes, shared by the live SceneView
 * (shared/scene_view.m) and Reel's offline renderer
 * (modules/reel/native/scene.m), so a model imports, resolves its textures
 * and samples its palette identically in the app and in a promo render.
 *
 * Each file loads once through SceneKit's importers (OBJ with its MTL and
 * textures, DAE, USDZ, SCN) into a prototype; every use is a clone sharing
 * its geometry and materials. */

static NSMutableDictionary<NSString *, SCNNode *> *scene_model_cache(void) {
	static NSMutableDictionary *cache;
	if (!cache) cache = [NSMutableDictionary dictionary];
	return cache;
}

/* OBJ materials name their textures relative to the model file; SceneKit
 * keeps those names as strings, which it would resolve against the working
 * directory. Resolve them against the model instead. */
static void scene_resolve_textures(SCNNode *root, NSURL *base) {
	[root enumerateHierarchyUsingBlock:^(SCNNode *node, BOOL *stop) {
		(void)stop;
		for (SCNMaterial *material in node.geometry.materials) {
			for (SCNMaterialProperty *property in @[material.diffuse, material.emission, material.normal,
					material.roughness, material.metalness, material.ambientOcclusion]) {
				id contents = property.contents;
				if ([contents isKindOfClass:NSString.class] && ![contents isAbsolutePath]) {
					property.contents = [NSURL fileURLWithPath:contents relativeToURL:base].absoluteURL;
				}
				/* Low-poly kits paint faces from a palette texture: sample it
				 * crisply so neighbouring swatches never bleed together. */
				property.magnificationFilter = SCNFilterModeNearest;
			}
		}
	}];
}

/* A fresh clone of the model at `path`, or nil with `error` set when the
 * file is missing or SceneKit cannot import it. */
static SCNNode *scene_model(NSString *path, NSString **error) {
	SCNNode *prototype = scene_model_cache()[path];
	if (!prototype) {
		if (![NSFileManager.defaultManager isReadableFileAtPath:path]) {
			if (error) *error = [NSString stringWithFormat:@"cannot read model %@", path];
			return nil;
		}
		NSURL *url = [NSURL fileURLWithPath:path];
		NSError *loadError = nil;
		SCNScene *scene = [SCNScene sceneWithURL:url options:nil error:&loadError];
		if (!scene) {
			if (error) *error = loadError.localizedDescription ?: @"unreadable model";
			return nil;
		}
		prototype = [SCNNode node];
		for (SCNNode *child in scene.rootNode.childNodes) [prototype addChildNode:child];
		scene_resolve_textures(prototype, url.URLByDeletingLastPathComponent);
		scene_model_cache()[path] = prototype;
	}
	return [prototype clone];
}
