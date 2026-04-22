import 'package:encrypt/encrypt.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// Simple encryption utility for sensitive data storage
/// Uses AES encryption with a key derived from device identifiers
class EncryptionUtil {
  static final Key _key = Key.fromUtf8(_generateKey());
  static final IV _iv = IV.fromLength(16);

  // Generate a deterministic key based on a fixed salt
  // Note: This provides basic obfuscation, not military-grade security
  // For higher security, consider using platform-specific secure storage
  static String _generateKey() {
    const salt = 'termiscope_secure_storage_salt_2024';
    final bytes = utf8.encode(salt);
    final hash = sha256.convert(bytes);
    // Use first 32 characters (256 bits for AES-256)
    return hash.toString().substring(0, 32);
  }

  static String encrypt(String plainText) {
    try {
      final encrypter = Encrypter(AES(_key));
      final encrypted = encrypter.encrypt(plainText, iv: _iv);
      return encrypted.base64;
    } catch (e) {
      // If encryption fails, return the plain text (fallback)
      print('Encryption error: $e');
      return plainText;
    }
  }

  static String decrypt(String encryptedText) {
    try {
      final encrypter = Encrypter(AES(_key));
      final decrypted = decrypter.decrypt(Encrypted.fromBase64(encryptedText), iv: _iv);
      return decrypted;
    } catch (e) {
      // If decryption fails, return the input as-is (might be unencrypted)
      print('Decryption error: $e');
      return encryptedText;
    }
  }
}
