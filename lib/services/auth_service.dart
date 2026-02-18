import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  static final AuthService instance = AuthService._init();
  AuthService._init();
  
  User? get currentUser => FirebaseAuth.instance.currentUser;
  String get currentUserEmail => currentUser?.email ?? 'Unknown';
  String get currentUserId => currentUser?.uid ?? '';
  
  Stream<User?> get authStateChanges => FirebaseAuth.instance.authStateChanges();
  
  Future<UserCredential> signIn(String email, String password) async {
    return await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
  }
}

