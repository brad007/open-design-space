import 'package:flutter_test/flutter_test.dart';
import 'package:open_design_space/ui/widgets.dart';

void main() {
  test('number formatting keeps whole-number zeros', () {
    expect(formatNumber(70, 0), '70');
    expect(formatNumber(10, 2), '10');
    expect(formatNumber(0, 0), '0');
    expect(formatNumber(1.5, 2), '1.5');
    expect(formatNumber(2.25, 2), '2.25');
    expect(formatNumber(-0.001, 2), '0');
    expect(formatNumber(-14.3, 1), '-14.3');
  });
}
