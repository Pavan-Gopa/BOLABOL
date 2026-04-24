#include <node_api.h>

static napi_value Init(napi_env env, napi_value exports) {
  napi_value errStr; napi_status s;
  const char *msg = "Vulkan SDK not available (stub).";
  s = napi_create_string_utf8(env, msg, NAPI_AUTO_LENGTH, &errStr);
  if (s == napi_ok) {
    napi_value global, consoleObj, consoleStr, logFn;
    if (napi_get_global(env, &global) == napi_ok &&
        napi_create_string_utf8(env, "console", NAPI_AUTO_LENGTH, &consoleStr) == napi_ok &&
        napi_get_property(env, global, consoleStr, &consoleObj) == napi_ok &&
        napi_create_string_utf8(env, "error", NAPI_AUTO_LENGTH, &consoleStr) == napi_ok &&
        napi_get_property(env, consoleObj, consoleStr, &logFn) == napi_ok) {
      napi_value argv[1] = { errStr }; napi_call_function(env, consoleObj, logFn, 1, argv, NULL);
    }
  }
  return exports;
}

NAPI_MODULE(NODE_GYP_MODULE_NAME, Init)
