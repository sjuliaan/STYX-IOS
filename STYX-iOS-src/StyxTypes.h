#pragma once

typedef struct { float x, y, z; } Styxi_Vector3;
typedef struct { float x, y, z, w; } Styxi_Quaternion;

// Il2Cpp object layouts
#define IL2CPP_OBJ_KLASS_OFF   0x00
#define IL2CPP_OBJ_MONITOR_OFF 0x08

// Il2CppList<T>: _items at 0x10, _size at 0x18
#define IL2CPP_LIST_ITEMS_OFF 0x10
#define IL2CPP_LIST_SIZE_OFF  0x18

// Il2CppArray: header 0x20 bytes, data follows
#define IL2CPP_ARRAY_DATA_OFF 0x20

// Il2CppString: _length int32 at 0x10, chars (UTF-16) at 0x14
#define IL2CPP_STRING_LEN_OFF  0x10
#define IL2CPP_STRING_CHARS_OFF 0x14