import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/reward_model.dart';
import '../../auth/data/auth_repository.dart';
import 'reward_service.dart';

/// Wrapper um den [RewardService] für Riverpod-Konsumenten, die einen
/// Stream pro Kind erwarten.
///
/// Vorher: Stub, der für alle Anfragen `Stream.value([])` zurückgab — das
/// hatte zur Folge dass alle Konsumenten leere Listen sahen. Da er nirgends
/// importiert war, fiel der Bug nicht direkt auf, aber bei zukünftigen
/// Refactorings (z.B. Family-Dashboard) wäre er ein Problem geworden.
///
/// Heute: leitet direkt an den funktionierenden [RewardService] weiter.
class RewardRepository {
  final RewardService _service;
  RewardRepository(this._service);

  /// Stream aller Belohnungen eines Kindes — benötigt zusätzlich die userId,
  /// die hier per Provider injiziert wird.
  Stream<List<RewardModel>> watchRewardsForChild({
    required String userId,
    required String childId,
  }) {
    return _service.getRewardsStream(userId: userId, childId: childId);
  }
}

/// Provider für [RewardRepository]
final rewardRepositoryProvider = Provider<RewardRepository>((ref) {
  final service = ref.watch(rewardServiceProvider);
  return RewardRepository(service);
});

/// Stream-Provider für die Belohnungen eines Kindes.
///
/// Nutzung:
///   final rewards = ref.watch(childRewardsProvider(childId));
///
/// Greift auf den aktuell eingeloggten User aus `authStateChangesProvider`
/// zu. Wenn niemand eingeloggt ist: leerer Stream.
final childRewardsProvider = StreamProvider.family<List<RewardModel>, String>((
  ref,
  childId,
) {
  final user = ref.watch(authStateChangesProvider).value;
  if (user == null) return Stream.value(const []);

  return ref
      .watch(rewardRepositoryProvider)
      .watchRewardsForChild(userId: user.uid, childId: childId);
});

/// Re-Export für Tests / Bequemlichkeit
typedef RewardRepo = RewardRepository;
