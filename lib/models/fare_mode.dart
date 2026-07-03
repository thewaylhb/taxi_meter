/// Fare calculation scheme.
enum FareMode {
  /// Standard metered fare based on Seoul medium-taxi rates.
  standard,

  /// Carpool cost-sharing mode: flat base fare + fuel-cost-based distance fare.
  carpool;

  String get label {
    switch (this) {
      case FareMode.standard:
        return '표준 미터 요금';
      case FareMode.carpool:
        return '카풀 모드';
    }
  }

  String get description {
    switch (this) {
      case FareMode.standard:
        return '서울시 중형택시 기준 거리·시간 병산 요금제';
      case FareMode.carpool:
        return '기본요금 3,000원 + 연비 기반 유류비 분담';
    }
  }
}
