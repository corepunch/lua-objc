#pragma mark - glTF 2.0 models

/* SceneKit imports OBJ, DAE, USD and SCN but not glTF, the format Kenney and
 * most low-poly kits ship. This reads binary glTF (.glb) and JSON glTF with
 * external buffers into an ordinary SceneKit node tree: nodes with their
 * TRS or matrix transforms, triangle meshes (positions, normals, texture
 * coordinates, 8-, 16- or 32-bit indices, interleaved or packed buffers),
 * base colour materials with KHR_texture_transform and KHR_materials_unlit,
 * skins as SCNSkinner, and animation clips as paused SCNAnimationPlayers
 * keyed "<clip>.<property>" on the nodes they move.
 *
 * glTF and SceneKit agree on units (metres), handedness (right), up (+Y),
 * quaternion order and column-major matrices, and both put texture
 * coordinate (0, 0) at the image's top-left, so values are copied as they
 * are. Morph targets, cameras, lights and compressed geometry are not read:
 * no kit this project uses carries them. */

typedef struct {
	NSData *data; /* the accessor's elements, tightly packed */
	NSInteger count, components, componentSize, componentType;
} SceneGLTFAccessor;

static NSInteger scene_gltf_component_size(NSInteger type) {
	switch (type) {
		case 5120: case 5121: return 1; /* BYTE, UNSIGNED_BYTE */
		case 5122: case 5123: return 2; /* SHORT, UNSIGNED_SHORT */
		case 5125: case 5126: return 4; /* UNSIGNED_INT, FLOAT */
		default: return 0;
	}
}

static NSInteger scene_gltf_components(NSString *type) {
	NSDictionary *counts = @{@"SCALAR": @1, @"VEC2": @2, @"VEC3": @3, @"VEC4": @4, @"MAT4": @16};
	return [counts[type] integerValue];
}

typedef struct {
	NSDictionary *json;
	NSArray<NSData *> *buffers;
	NSURL *base;
	NSString *error;
} SceneGLTFFile;

static NSData *scene_gltf_view(SceneGLTFFile *file, NSInteger index, NSInteger *stride) {
	NSArray *views = file->json[@"bufferViews"];
	if (index < 0 || index >= (NSInteger)views.count) return nil;
	NSDictionary *view = views[index];
	NSInteger buffer = [view[@"buffer"] integerValue];
	if (buffer < 0 || buffer >= (NSInteger)file->buffers.count) return nil;
	NSData *data = file->buffers[buffer];
	NSInteger offset = [view[@"byteOffset"] integerValue], length = [view[@"byteLength"] integerValue];
	if (offset < 0 || length < 0 || offset + length > (NSInteger)data.length) return nil;
	if (stride) *stride = [view[@"byteStride"] integerValue];
	return [data subdataWithRange:NSMakeRange(offset, length)];
}

static BOOL scene_gltf_accessor(SceneGLTFFile *file, id indexValue, SceneGLTFAccessor *out) {
	NSArray *accessors = file->json[@"accessors"];
	if (![indexValue isKindOfClass:NSNumber.class]) return NO;
	NSInteger index = [indexValue integerValue];
	if (index < 0 || index >= (NSInteger)accessors.count) return NO;
	NSDictionary *accessor = accessors[index];
	if (accessor[@"sparse"]) { file->error = @"sparse accessors are not supported"; return NO; }
	SceneGLTFAccessor result = {0};
	result.count = [accessor[@"count"] integerValue];
	result.componentType = [accessor[@"componentType"] integerValue];
	result.componentSize = scene_gltf_component_size(result.componentType);
	result.components = scene_gltf_components(accessor[@"type"]);
	if (!result.componentSize || !result.components || result.count < 0) return NO;
	NSInteger element = result.componentSize * result.components;
	NSMutableData *packed = [NSMutableData dataWithLength:(NSUInteger)(element * result.count)];
	if (accessor[@"bufferView"]) {
		NSInteger stride = 0;
		NSData *view = scene_gltf_view(file, [accessor[@"bufferView"] integerValue], &stride);
		if (!view) return NO;
		if (stride <= 0) stride = element;
		NSInteger offset = [accessor[@"byteOffset"] integerValue];
		if (result.count > 0 && offset + stride * (result.count - 1) + element > (NSInteger)view.length) return NO;
		const uint8_t *source = (const uint8_t *)view.bytes + offset;
		uint8_t *target = packed.mutableBytes;
		for (NSInteger i = 0; i < result.count; i++) memcpy(target + i * element, source + i * stride, (size_t)element);
	}
	result.data = packed;
	*out = result;
	return YES;
}

/* Accessors read as floats: the normalized integer forms glTF allows for
 * texture coordinates and weights become floats in 0...1. */
static NSData *scene_gltf_floats(SceneGLTFAccessor accessor) {
	if (accessor.componentType == 5126) return accessor.data;
	NSInteger total = accessor.count * accessor.components;
	NSMutableData *floats = [NSMutableData dataWithLength:(NSUInteger)total * sizeof(float)];
	float *target = floats.mutableBytes;
	const uint8_t *bytes = accessor.data.bytes;
	for (NSInteger i = 0; i < total; i++) {
		switch (accessor.componentType) {
			case 5121: target[i] = bytes[i] / 255.0f; break;
			case 5123: target[i] = ((const uint16_t *)bytes)[i] / 65535.0f; break;
			case 5120: target[i] = fmaxf(((const int8_t *)bytes)[i] / 127.0f, -1); break;
			case 5122: target[i] = fmaxf(((const int16_t *)bytes)[i] / 32767.0f, -1); break;
			default: target[i] = ((const uint32_t *)bytes)[i]; break;
		}
	}
	return floats;
}

/* Unsigned integers widened to 16 or 32 bits, for indices and joints. */
static NSData *scene_gltf_integers(SceneGLTFAccessor accessor, NSInteger *size) {
	NSInteger total = accessor.count * accessor.components;
	BOOL wide = accessor.componentType == 5125;
	if (accessor.componentType == 5123 || wide) { *size = wide ? 4 : 2; return accessor.data; }
	NSMutableData *shorts = [NSMutableData dataWithLength:(NSUInteger)total * sizeof(uint16_t)];
	const uint8_t *bytes = accessor.data.bytes;
	uint16_t *target = shorts.mutableBytes;
	for (NSInteger i = 0; i < total; i++) target[i] = bytes[i];
	*size = 2;
	return shorts;
}

static SCNGeometrySource *scene_gltf_source(SceneGLTFFile *file, id index, SCNGeometrySourceSemantic semantic) {
	SceneGLTFAccessor accessor;
	if (!scene_gltf_accessor(file, index, &accessor)) return nil;
	NSData *floats = scene_gltf_floats(accessor);
	return [SCNGeometrySource geometrySourceWithData:floats semantic:semantic vectorCount:accessor.count
		floatComponents:YES componentsPerVector:accessor.components bytesPerComponent:sizeof(float)
		dataOffset:0 dataStride:accessor.components * (NSInteger)sizeof(float)];
}

static SCNWrapMode scene_gltf_wrap(id mode) {
	switch ([mode integerValue]) {
		case 33071: return SCNWrapModeClamp;
		case 33648: return SCNWrapModeMirror;
		default: return SCNWrapModeRepeat;
	}
}

static id scene_gltf_image(SceneGLTFFile *file, NSInteger index) {
	NSArray *images = file->json[@"images"];
	if (index < 0 || index >= (NSInteger)images.count) return nil;
	NSDictionary *image = images[index];
	NSString *uri = image[@"uri"];
	if ([uri isKindOfClass:NSString.class] && ![uri hasPrefix:@"data:"]) {
		/* A URL, like an OBJ's map_Kd: SceneKit loads it, and
		 * scene_resolve_textures has nothing left to resolve. */
		NSString *path = [uri stringByRemovingPercentEncoding] ?: uri;
		return [NSURL fileURLWithPath:path relativeToURL:file->base].absoluteURL;
	}
	NSData *data = nil;
	if ([uri isKindOfClass:NSString.class]) {
		NSRange comma = [uri rangeOfString:@","];
		if (comma.location != NSNotFound)
			data = [[NSData alloc] initWithBase64EncodedString:[uri substringFromIndex:comma.location + 1] options:0];
	} else if (image[@"bufferView"]) {
		data = scene_gltf_view(file, [image[@"bufferView"] integerValue], NULL);
	}
	if (!data) return nil;
#if TARGET_OS_IPHONE
	return [UIImage imageWithData:data];
#else
	return [[NSImage alloc] initWithData:data];
#endif
}

static SCNMaterial *scene_gltf_material(SceneGLTFFile *file, id indexValue) {
	SCNMaterial *material = [SCNMaterial material];
	material.lightingModelName = SCNLightingModelBlinn;
	NSArray *materials = file->json[@"materials"];
	if (![indexValue isKindOfClass:NSNumber.class] || [indexValue integerValue] >= (NSInteger)materials.count)
		return material;
	NSDictionary *source = materials[[indexValue integerValue]];
	material.name = source[@"name"];
	material.doubleSided = [source[@"doubleSided"] boolValue];
	if (source[@"extensions"][@"KHR_materials_unlit"]) material.lightingModelName = SCNLightingModelConstant;
	NSDictionary *pbr = source[@"pbrMetallicRoughness"];
	NSArray *factor = pbr[@"baseColorFactor"];
	CGFloat rgba[4] = {1, 1, 1, 1};
	if ([factor isKindOfClass:NSArray.class] && factor.count == 4)
		for (int i = 0; i < 4; i++) rgba[i] = [factor[i] doubleValue];
	/* glTF colour factors are linear, not sRGB-encoded: older kits (Racing,
	 * Space) colour whole meshes this way and would render too dark. */
	CGColorSpaceRef linear = CGColorSpaceCreateWithName(kCGColorSpaceLinearSRGB);
	CGColorRef cgColor = CGColorCreate(linear, rgba);
#if TARGET_OS_IPHONE
	id color = [UIColor colorWithCGColor:cgColor];
#else
	id color = [NSColor colorWithCGColor:cgColor];
#endif
	CGColorRelease(cgColor);
	CGColorSpaceRelease(linear);
	NSDictionary *textureInfo = pbr[@"baseColorTexture"];
	NSArray *textures = file->json[@"textures"];
	NSInteger textureIndex = textureInfo ? [textureInfo[@"index"] integerValue] : -1;
	if (textureIndex >= 0 && textureIndex < (NSInteger)textures.count) {
		NSDictionary *texture = textures[textureIndex];
		id image = scene_gltf_image(file, [texture[@"source"] integerValue]);
		if (image) {
			material.diffuse.contents = image;
			BOOL tinted = rgba[0] != 1 || rgba[1] != 1 || rgba[2] != 1;
			if (tinted) material.multiply.contents = color;
			NSArray *samplers = file->json[@"samplers"];
			NSInteger samplerIndex = texture[@"sampler"] ? [texture[@"sampler"] integerValue] : -1;
			NSDictionary *sampler = samplerIndex >= 0 && samplerIndex < (NSInteger)samplers.count ? samplers[samplerIndex] : @{};
			material.diffuse.wrapS = scene_gltf_wrap(sampler[@"wrapS"]);
			material.diffuse.wrapT = scene_gltf_wrap(sampler[@"wrapT"]);
			NSDictionary *transform = textureInfo[@"extensions"][@"KHR_texture_transform"];
			if (transform) {
				NSArray *offset = transform[@"offset"], *scale = transform[@"scale"];
				double rotation = [transform[@"rotation"] doubleValue];
				SCNMatrix4 matrix = SCNMatrix4Identity;
				if (scale.count == 2) matrix = SCNMatrix4Scale(matrix, [scale[0] doubleValue], [scale[1] doubleValue], 1);
				if (rotation) matrix = SCNMatrix4Rotate(matrix, -rotation, 0, 0, 1);
				if (offset.count == 2) matrix = SCNMatrix4Translate(matrix, [offset[0] doubleValue], [offset[1] doubleValue], 0);
				material.diffuse.contentsTransform = matrix;
			}
		} else {
			material.diffuse.contents = color;
		}
	} else {
		material.diffuse.contents = color;
	}
	if (rgba[3] < 1 || [source[@"alphaMode"] isEqual:@"BLEND"]) {
		material.transparencyMode = SCNTransparencyModeDualLayer;
		material.blendMode = SCNBlendModeAlpha;
	}
	return material;
}

/* One geometry per primitive; positions are required, the rest optional. */
static SCNGeometry *scene_gltf_primitive(SceneGLTFFile *file, NSDictionary *primitive,
		SCNGeometrySource **joints, SCNGeometrySource **weights) {
	NSInteger mode = primitive[@"mode"] ? [primitive[@"mode"] integerValue] : 4;
	if (mode != 4) return nil; /* triangles only; lines and strips are not drawn */
	NSDictionary *attributes = primitive[@"attributes"];
	NSMutableArray *sources = [NSMutableArray array];
	SCNGeometrySource *position = scene_gltf_source(file, attributes[@"POSITION"], SCNGeometrySourceSemanticVertex);
	if (!position) return nil;
	[sources addObject:position];
	SCNGeometrySource *normal = scene_gltf_source(file, attributes[@"NORMAL"], SCNGeometrySourceSemanticNormal);
	if (normal) [sources addObject:normal];
	SCNGeometrySource *uv = scene_gltf_source(file, attributes[@"TEXCOORD_0"], SCNGeometrySourceSemanticTexcoord);
	if (uv) [sources addObject:uv];
	SCNGeometrySource *color = scene_gltf_source(file, attributes[@"COLOR_0"], SCNGeometrySourceSemanticColor);
	if (color) [sources addObject:color];
	SCNGeometryElement *element;
	SceneGLTFAccessor indices;
	if (scene_gltf_accessor(file, primitive[@"indices"], &indices)) {
		NSInteger size = 0;
		NSData *data = scene_gltf_integers(indices, &size);
		element = [SCNGeometryElement geometryElementWithData:data primitiveType:SCNGeometryPrimitiveTypeTriangles
			primitiveCount:indices.count / 3 bytesPerIndex:size];
	} else {
		NSInteger count = position.vectorCount;
		NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)count * sizeof(uint32_t)];
		uint32_t *target = data.mutableBytes;
		for (NSInteger i = 0; i < count; i++) target[i] = (uint32_t)i;
		element = [SCNGeometryElement geometryElementWithData:data primitiveType:SCNGeometryPrimitiveTypeTriangles
			primitiveCount:count / 3 bytesPerIndex:sizeof(uint32_t)];
	}
	SCNGeometry *geometry = [SCNGeometry geometryWithSources:sources elements:@[element]];
	geometry.materials = @[scene_gltf_material(file, primitive[@"material"])];
	SceneGLTFAccessor jointData;
	if (joints && weights && scene_gltf_accessor(file, attributes[@"JOINTS_0"], &jointData)) {
		NSInteger size = 0;
		NSData *data = scene_gltf_integers(jointData, &size);
		*joints = [SCNGeometrySource geometrySourceWithData:data semantic:SCNGeometrySourceSemanticBoneIndices
			vectorCount:jointData.count floatComponents:NO componentsPerVector:jointData.components
			bytesPerComponent:size dataOffset:0 dataStride:jointData.components * size];
		*weights = scene_gltf_source(file, attributes[@"WEIGHTS_0"], SCNGeometrySourceSemanticBoneWeights);
	}
	return geometry;
}

static simd_float4x4 scene_gltf_matrix(NSArray *values) {
	simd_float4x4 matrix = matrix_identity_float4x4;
	if (values.count == 16)
		for (int column = 0; column < 4; column++)
			for (int row = 0; row < 4; row++) matrix.columns[column][row] = [values[column * 4 + row] floatValue];
	return matrix;
}

static void scene_gltf_transform(SCNNode *node, NSDictionary *source) {
	NSArray *matrix = source[@"matrix"], *t = source[@"translation"], *r = source[@"rotation"], *s = source[@"scale"];
	if (matrix.count == 16) { node.simdTransform = scene_gltf_matrix(matrix); return; }
	if (t.count == 3) node.simdPosition = simd_make_float3([t[0] floatValue], [t[1] floatValue], [t[2] floatValue]);
	if (r.count == 4) node.simdOrientation = simd_quaternion([r[0] floatValue], [r[1] floatValue], [r[2] floatValue], [r[3] floatValue]);
	if (s.count == 3) node.simdScale = simd_make_float3([s[0] floatValue], [s[1] floatValue], [s[2] floatValue]);
}

static void scene_gltf_skin(SceneGLTFFile *file, SCNNode *meshNode, NSInteger skinIndex, NSArray<SCNNode *> *nodes,
		SCNGeometrySource *joints, SCNGeometrySource *weights) {
	NSArray *skins = file->json[@"skins"];
	if (skinIndex < 0 || skinIndex >= (NSInteger)skins.count || !joints || !weights) return;
	NSDictionary *skin = skins[skinIndex];
	NSMutableArray<SCNNode *> *bones = [NSMutableArray array];
	for (NSNumber *joint in skin[@"joints"]) {
		NSInteger index = joint.integerValue;
		if (index < 0 || index >= (NSInteger)nodes.count) return;
		[bones addObject:nodes[index]];
	}
	NSMutableArray<NSValue *> *inverse = [NSMutableArray array];
	SceneGLTFAccessor matrices;
	BOOL haveMatrices = scene_gltf_accessor(file, skin[@"inverseBindMatrices"], &matrices) && matrices.components == 16
		&& matrices.count >= (NSInteger)bones.count && matrices.componentType == 5126;
	for (NSUInteger i = 0; i < bones.count; i++) {
		simd_float4x4 matrix = matrix_identity_float4x4;
		if (haveMatrices) memcpy(&matrix, (const float *)matrices.data.bytes + i * 16, sizeof(matrix));
		[inverse addObject:[NSValue valueWithSCNMatrix4:SCNMatrix4FromMat4(matrix)]];
	}
	SCNSkinner *skinner = [SCNSkinner skinnerWithBaseGeometry:meshNode.geometry bones:bones
		boneInverseBindTransforms:inverse boneWeights:weights boneIndices:joints];
	NSNumber *skeleton = skin[@"skeleton"];
	if (skeleton && skeleton.integerValue >= 0 && skeleton.integerValue < (NSInteger)nodes.count)
		skinner.skeleton = nodes[skeleton.integerValue];
	meshNode.skinner = skinner;
}

/* Each clip becomes, on every node it moves, one paused SCNAnimationPlayer
 * per animated property, keyed "<clip>.<property>". The keys travel with a
 * clone, so playing a clip is finding its keys in the clone's hierarchy. */
static void scene_gltf_animations(SceneGLTFFile *file, NSArray<SCNNode *> *nodes) {
	NSArray *animations = file->json[@"animations"];
	[animations enumerateObjectsUsingBlock:^(NSDictionary *animation, NSUInteger clipIndex, BOOL *stop) {
		(void)stop;
		NSString *clip = [animation[@"name"] isKindOfClass:NSString.class] && [animation[@"name"] length]
			? animation[@"name"] : [NSString stringWithFormat:@"clip-%lu", (unsigned long)clipIndex];
		NSArray *samplers = animation[@"samplers"];
		for (NSDictionary *channel in animation[@"channels"]) {
			NSDictionary *target = channel[@"target"];
			NSInteger nodeIndex = [target[@"node"] integerValue], samplerIndex = [channel[@"sampler"] integerValue];
			NSString *path = target[@"path"];
			NSString *keyPath = @{@"translation": @"position", @"rotation": @"orientation", @"scale": @"scale"}[path];
			if (!keyPath || nodeIndex < 0 || nodeIndex >= (NSInteger)nodes.count
					|| samplerIndex < 0 || samplerIndex >= (NSInteger)samplers.count) continue;
			NSDictionary *sampler = samplers[samplerIndex];
			SceneGLTFAccessor input, output;
			if (!scene_gltf_accessor(file, sampler[@"input"], &input) || !scene_gltf_accessor(file, sampler[@"output"], &output)) continue;
			NSData *times = scene_gltf_floats(input), *values = scene_gltf_floats(output);
			BOOL cubic = [sampler[@"interpolation"] isEqual:@"CUBICSPLINE"];
			NSInteger width = [path isEqual:@"rotation"] ? 4 : 3, count = input.count;
			if (count < 1 || output.count * output.components < count * width * (cubic ? 3 : 1)) continue;
			const float *t = times.bytes, *v = values.bytes;
			float duration = t[count - 1];
			NSMutableArray *keyValues = [NSMutableArray array], *keyTimes = [NSMutableArray array];
			for (NSInteger i = 0; i < count; i++) {
				/* A cubic spline stores in-tangent, value, out-tangent; keep the value. */
				const float *k = v + (cubic ? (i * 3 + 1) : i) * width;
				[keyTimes addObject:@(duration > 0 ? t[i] / duration : 0)];
				if (width == 4) [keyValues addObject:[NSValue valueWithSCNVector4:SCNVector4Make(k[0], k[1], k[2], k[3])]];
				else [keyValues addObject:[NSValue valueWithSCNVector3:SCNVector3Make(k[0], k[1], k[2])]];
			}
			CAKeyframeAnimation *keyframes = [CAKeyframeAnimation animationWithKeyPath:keyPath];
			keyframes.values = keyValues;
			keyframes.keyTimes = keyTimes;
			keyframes.duration = MAX(duration, 1.0 / 60);
			keyframes.calculationMode = [sampler[@"interpolation"] isEqual:@"STEP"] ? kCAAnimationDiscrete : kCAAnimationLinear;
			SCNAnimation *scnAnimation = [SCNAnimation animationWithCAAnimation:keyframes];
			scnAnimation.repeatCount = HUGE_VALF;
			scnAnimation.blendInDuration = 0.15;
			scnAnimation.blendOutDuration = 0.15;
			SCNAnimationPlayer *player = [SCNAnimationPlayer animationPlayerWithAnimation:scnAnimation];
			player.paused = YES;
			[nodes[nodeIndex] addAnimationPlayer:player forKey:[NSString stringWithFormat:@"%@.%@", clip, keyPath]];
		}
	}];
}

static NSArray<NSData *> *scene_gltf_buffers(NSDictionary *json, NSData *binary, NSURL *base, NSString **error) {
	NSMutableArray<NSData *> *buffers = [NSMutableArray array];
	for (NSDictionary *buffer in json[@"buffers"]) {
		NSString *uri = buffer[@"uri"];
		NSData *data = nil;
		if (![uri isKindOfClass:NSString.class]) data = binary;
		else if ([uri hasPrefix:@"data:"]) {
			NSRange comma = [uri rangeOfString:@","];
			if (comma.location != NSNotFound)
				data = [[NSData alloc] initWithBase64EncodedString:[uri substringFromIndex:comma.location + 1] options:0];
		} else {
			NSString *path = [uri stringByRemovingPercentEncoding] ?: uri;
			data = [NSData dataWithContentsOfURL:[NSURL fileURLWithPath:path relativeToURL:base]];
		}
		if (!data || (NSInteger)data.length < [buffer[@"byteLength"] integerValue]) {
			*error = @"a glTF buffer is missing or short";
			return nil;
		}
		[buffers addObject:data];
	}
	return buffers;
}

/* The root of the file's default scene, or nil with `error` set. */
static SCNNode *scene_gltf_load(NSURL *url, NSString **error) {
	NSData *file = [NSData dataWithContentsOfURL:url];
	if (!file) { if (error) *error = @"unreadable model"; return nil; }
	NSData *jsonData = file, *binary = nil;
	const uint8_t *bytes = file.bytes;
	if (file.length >= 12 && memcmp(bytes, "glTF", 4) == 0) {
		/* GLB: header, a JSON chunk, then an optional BIN chunk. */
		uint32_t length = 0, chunkLength = 0, chunkType = 0;
		memcpy(&length, bytes + 8, 4);
		NSUInteger offset = 12;
		jsonData = nil;
		while (offset + 8 <= MIN(length, file.length)) {
			memcpy(&chunkLength, bytes + offset, 4);
			memcpy(&chunkType, bytes + offset + 4, 4);
			if (offset + 8 + chunkLength > file.length) break;
			NSData *chunk = [file subdataWithRange:NSMakeRange(offset + 8, chunkLength)];
			if (chunkType == 0x4E4F534A) jsonData = chunk; /* "JSON" */
			else if (chunkType == 0x004E4942) binary = chunk; /* "BIN\0" */
			offset += 8 + ((chunkLength + 3) & ~3u);
		}
	}
	NSDictionary *json = jsonData ? [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:NULL] : nil;
	if (![json isKindOfClass:NSDictionary.class]) { if (error) *error = @"not a glTF file"; return nil; }
	NSString *failure = nil;
	NSURL *base = url.URLByDeletingLastPathComponent;
	NSArray *buffers = scene_gltf_buffers(json, binary, base, &failure);
	if (!buffers) { if (error) *error = failure; return nil; }
	__block SceneGLTFFile gltf = {json, buffers, base, nil};
	NSArray *sources = json[@"nodes"];
	NSMutableArray<SCNNode *> *nodes = [NSMutableArray array];
	for (NSDictionary *source in sources) {
		SCNNode *node = [SCNNode node];
		if ([source[@"name"] isKindOfClass:NSString.class]) node.name = source[@"name"];
		scene_gltf_transform(node, source);
		[nodes addObject:node];
	}
	NSArray *meshes = json[@"meshes"];
	NSMutableSet<NSNumber *> *children = [NSMutableSet set];
	[sources enumerateObjectsUsingBlock:^(NSDictionary *source, NSUInteger index, BOOL *stop) {
		(void)stop;
		SCNNode *node = nodes[index];
		for (NSNumber *child in source[@"children"]) {
			NSInteger childIndex = child.integerValue;
			if (childIndex < 0 || childIndex >= (NSInteger)nodes.count || [children containsObject:child]) continue;
			[children addObject:child];
			[node addChildNode:nodes[childIndex]];
		}
		NSNumber *mesh = source[@"mesh"];
		if (!mesh || mesh.integerValue < 0 || mesh.integerValue >= (NSInteger)meshes.count) return;
		NSArray *primitives = meshes[mesh.integerValue][@"primitives"];
		BOOL skinned = source[@"skin"] != nil;
		for (NSDictionary *primitive in primitives) {
			SCNGeometrySource *joints = nil, *weights = nil;
			SCNGeometry *geometry = scene_gltf_primitive(&gltf, primitive, skinned ? &joints : NULL, skinned ? &weights : NULL);
			if (!geometry) continue;
			/* The first primitive draws on the node itself, the rest on children. */
			SCNNode *target = node.geometry ? [SCNNode node] : node;
			if (target != node) [node addChildNode:target];
			target.geometry = geometry;
			if (skinned) {
				/* glTF ignores a skinned mesh's own transform: joints place it. */
				node.simdTransform = matrix_identity_float4x4;
				scene_gltf_skin(&gltf, target, [source[@"skin"] integerValue], nodes, joints, weights);
			}
		}
	}];
	if (gltf.error) { if (error) *error = gltf.error; return nil; }
	SCNNode *root = [SCNNode node];
	NSArray *scenes = json[@"scenes"];
	NSInteger sceneIndex = json[@"scene"] ? [json[@"scene"] integerValue] : 0;
	NSArray *roots = sceneIndex >= 0 && sceneIndex < (NSInteger)scenes.count ? scenes[sceneIndex][@"nodes"] : nil;
	if (!roots) {
		NSMutableArray *all = [NSMutableArray array];
		for (NSUInteger i = 0; i < nodes.count; i++) if (![children containsObject:@(i)]) [all addObject:@(i)];
		roots = all;
	}
	for (NSNumber *index in roots)
		if (index.integerValue >= 0 && index.integerValue < (NSInteger)nodes.count && !nodes[index.integerValue].parentNode)
			[root addChildNode:nodes[index.integerValue]];
	scene_gltf_animations(&gltf, nodes);
	return root;
}

/* Plays clip `name` on a model clone and stops any other, blending between
 * them; nil or an unknown name leaves the model in its rest pose. Returns
 * whether the clip exists. SceneKit runs the players, so nothing here ticks. */
__attribute__((unused)) static BOOL scene_model_play(SCNNode *model, NSString *name) {
	__block BOOL found = NO;
	NSString *prefix = name.length ? [name stringByAppendingString:@"."] : nil;
	[model enumerateHierarchyUsingBlock:^(SCNNode *node, BOOL *stop) {
		(void)stop;
		for (NSString *key in node.animationKeys) {
			SCNAnimationPlayer *player = [node animationPlayerForKey:key];
			if (prefix && [key hasPrefix:prefix]) {
				found = YES;
				if (player.paused) { player.paused = NO; [player play]; }
			} else if (!player.paused) {
				[player stopWithBlendOutDuration:player.animation.blendOutDuration];
				player.paused = YES;
			}
		}
	}];
	return found;
}

/* The clips a model carries, sorted, for tests and diagnostics. */
__attribute__((unused)) static NSArray<NSString *> *scene_model_clips(SCNNode *model) {
	NSMutableSet<NSString *> *clips = [NSMutableSet set];
	[model enumerateHierarchyUsingBlock:^(SCNNode *node, BOOL *stop) {
		(void)stop;
		for (NSString *key in node.animationKeys) {
			NSRange dot = [key rangeOfString:@"." options:NSBackwardsSearch];
			if (dot.location != NSNotFound) [clips addObject:[key substringToIndex:dot.location]];
		}
	}];
	return [clips.allObjects sortedArrayUsingSelector:@selector(compare:)];
}
