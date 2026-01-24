import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';
import '../models/user.dart';

final userApiProvider = Provider((ref) => UserApi(ref.read(apiClientProvider)));

class UserApi {
  final ApiClient _client;

  UserApi(this._client);

  Future<List<User>> getUsers() async {
    final response = await _client.get('/users');
    return (response as List).map((e) => User.fromJson(e)).toList();
  }

  Future<void> createUser(Map<String, dynamic> data) async {
    await _client.post('/users', data: data);
  }

  Future<void> updateUser(int id, Map<String, dynamic> data) async {
    await _client.put('/users/$id', data: data);
  }

  Future<void> deleteUser(int id) async {
    await _client.delete('/users/$id');
  }
}
