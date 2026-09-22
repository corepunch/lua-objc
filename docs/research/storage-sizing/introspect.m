#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
int main(int argc, char **argv) { @autoreleasepool {
	const char *paths[] = {"/System/Library/PrivateFrameworks/SpaceAttribution.framework/SpaceAttribution", "/System/Library/PrivateFrameworks/StorageManagement.framework/StorageManagement"};
	for(int i=0;i<2;i++) { if(!dlopen(paths[i],RTLD_NOW)) fprintf(stderr,"%s\n",dlerror()); }
	unsigned count=0; Class *classes=objc_copyClassList(&count);
	for(unsigned i=0;i<count;i++) { const char *name=class_getName(classes[i]);
		if (argc>1 ? !strstr(name,argv[1]) : strncmp(name,"SA",2)!=0) continue;
		printf("CLASS %s : %s\n", name, class_getName(class_getSuperclass(classes[i])));
		for(int meta=0;meta<2;meta++) { unsigned n=0; Method *methods=class_copyMethodList(meta?object_getClass(classes[i]):classes[i],&n);
			for(unsigned j=0;j<n;j++) printf("%c %s %s\n",meta?'+':'-',sel_getName(method_getName(methods[j])),method_getTypeEncoding(methods[j])); free(methods);
		}
	} free(classes);
} }
