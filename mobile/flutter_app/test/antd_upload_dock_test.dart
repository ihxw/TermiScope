import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termiscope_mobile/widgets/antd/antd_upload_dock.dart';

void main() {
  testWidgets('failed tasks expose retry and invoke the task callback',
      (tester) async {
    String? retried;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AntdUploadProgressDock(
          tasks: const [
            AntdUploadTask(
              id: 'failed-1',
              name: 'archive.zip',
              totalBytes: 100,
              uploadedBytes: 40,
              status: AntdUploadStatus.failed,
            ),
          ],
          onRetry: (id) => retried = id,
        ),
      ),
    ));

    expect(find.text('重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    expect(retried, 'failed-1');
  });

  testWidgets('uploading tasks expose cancel instead of retry', (tester) async {
    String? cancelled;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AntdUploadProgressDock(
          tasks: const [
            AntdUploadTask(
              id: 'active-1',
              name: 'video.mp4',
              totalBytes: 100,
            ),
          ],
          onCancel: (id) => cancelled = id,
          onRetry: (_) {},
        ),
      ),
    ));

    expect(find.text('重试'), findsNothing);
    await tester.tap(find.text('取消'));
    expect(cancelled, 'active-1');
  });
}
