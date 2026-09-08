/// A reserved contract only. No implementation, dependency, screen or request.
abstract interface class MarketRepository {
  Future<List<MarketQuote>> quotesFor(int typeId, int regionId);
}

class MarketQuote {
  const MarketQuote({
    required this.typeId,
    required this.price,
    required this.quantity,
  });
  final int typeId;
  final double price;
  final int quantity;
}
