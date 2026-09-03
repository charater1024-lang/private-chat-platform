import 'package:flutter/material.dart';

import 'app/secure_collab_app.dart';

export 'app/secure_collab_app.dart';
export 'features/workspace/secure_workspace_page.dart'
    show buildSecureCollabPreviewHomeserver;

void main() => runApp(const SecureCollabApp());
