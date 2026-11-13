#include "my_application.h"

#include <cstdlib>
#include <sys/prctl.h>
#include <sys/resource.h>

int main(int argc, char** argv) {
  const rlimit no_core_dumps = {0, 0};
  if (setrlimit(RLIMIT_CORE, &no_core_dumps) != 0 ||
      prctl(PR_SET_DUMPABLE, 0, 0, 0, 0) != 0) {
    return EXIT_FAILURE;
  }

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
