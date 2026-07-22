import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termiscope_mobile/widgets/antd/antd_button.dart';
import 'package:termiscope_mobile/widgets/antd/antd_dropdown.dart';

void main() {
  testWidgets('renders pure dividers without a blank item and disables actions',
      (tester) async {
    String? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AntdDropdown<String>(
            items: const [
              AntdDropdownItem(value: 'enabled', label: 'Enabled'),
              AntdDropdownItem(
                value: 'divider',
                label: '',
                divider: true,
              ),
              AntdDropdownItem(
                value: 'disabled',
                label: 'Disabled',
                disabled: true,
              ),
            ],
            onSelected: (value) => selected = value,
            child: AntdButton(
              onPressed: () {},
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(tester.getCenter(find.byType(AntdButton)));
    await tester.pumpAndSettle();

    expect(find.byType(PopupMenuDivider), findsOneWidget);
    expect(find.byType(PopupMenuItem<String>), findsNWidgets(2));
    await tester.tap(find.text('Disabled'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(tester.takeException(), isNull);
  });
}
