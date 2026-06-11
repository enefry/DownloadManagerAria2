#include <aria2/aria2.h>

#include <iostream>

int main() {
  if (aria2::libraryInit() != 0) {
    std::cerr << "libraryInit failed\n";
    return 1;
  }

  aria2::SessionConfig config;
  config.keepRunning = false;
  config.useSignalHandler = false;

  aria2::KeyVals options;
  options.emplace_back("dir", ".");
  options.emplace_back("quiet", "true");
  options.emplace_back("enable-rpc", "false");

  aria2::Session* session = aria2::sessionNew(options, config);
  if (!session) {
    std::cerr << "sessionNew failed\n";
    aria2::libraryDeinit();
    return 2;
  }

  int runResult = aria2::run(session, aria2::RUN_ONCE);
  int finalResult = aria2::sessionFinal(session);
  int deinitResult = aria2::libraryDeinit();

  if (runResult < 0 || finalResult != 0 || deinitResult != 0) {
    std::cerr << "run=" << runResult << " final=" << finalResult
              << " deinit=" << deinitResult << "\n";
    return 3;
  }

  std::cout << "libaria2 smoke ok\n";
  return 0;
}
