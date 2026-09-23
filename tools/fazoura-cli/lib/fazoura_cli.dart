/// Drives a Fazoura Party server from the terminal: host and join rooms, run
/// bots, and build, publish and manage quizzes — through the same client code
/// the app uses (`app/lib/core`), so what works here works there.
library;

export 'src/runner.dart' show runFazoura;
export 'src/socket_noise.dart' show absorbSocketNoise;
