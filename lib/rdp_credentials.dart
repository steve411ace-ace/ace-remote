import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Shared with PIN storage. RDP uses a separate encrypted preferences file.
const storage = FlutterSecureStorage();
const rdpPasswordKey = 'rdp_password';
const rdpStorageOptions = AndroidOptions(
  encryptedSharedPreferences: true,
  sharedPreferencesName: 'ace_rdp_credentials',
);
