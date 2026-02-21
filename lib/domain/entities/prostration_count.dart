import 'package:equatable/equatable.dart';

class ProstrationCount extends Equatable {
  final int totalCount;
  final int sessionCount;
  final String? lastSessionDate;

  const ProstrationCount({
    required this.totalCount,
    required this.sessionCount,
    this.lastSessionDate,
  });

  ProstrationCount copyWith({
    int? totalCount,
    int? sessionCount,
    String? lastSessionDate,
  }) {
    return ProstrationCount(
      totalCount: totalCount ?? this.totalCount,
      sessionCount: sessionCount ?? this.sessionCount,
      lastSessionDate: lastSessionDate ?? this.lastSessionDate,
    );
  }

  @override
  List<Object?> get props => [totalCount, sessionCount, lastSessionDate];
}
