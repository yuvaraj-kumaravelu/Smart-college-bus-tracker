import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'landing_page.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController(); 

  String? _verificationId;
  bool _otpSent = false;
  bool _isDriver = false;
  bool _loading = false;

  void _sendOTP() async {
    String phone = "+91${_phoneController.text.trim()}";
    if (phone.length < 13) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Enter a valid phone number")),
      );
      return;
    }

    setState(() => _loading = true);

    await _auth.verifyPhoneNumber(
      phoneNumber: phone,
      verificationCompleted: (PhoneAuthCredential credential) async {
        await _auth.signInWithCredential(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Verification failed: ${e.message}")),
        );
        setState(() => _loading = false);
      },
      codeSent: (String verificationId, int? resendToken) {
        setState(() {
          _otpSent = true;
          _verificationId = verificationId;
          _loading = false;
        });
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  void _verifyOTP() async {
    setState(() => _loading = true);
    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _otpController.text.trim(),
      );

      UserCredential userCredential = await _auth.signInWithCredential(credential);
      User? user = userCredential.user;

      if (user != null) {
        String phone = user.phoneNumber ?? "";

        // Step 1: If logging in as Driver, check Realtime DB whitelist
        if (_isDriver) {
          final snapshot = await FirebaseDatabase.instance
              .ref("drivers")
              .child(phone)
              .get();

          if (!snapshot.exists) {
            await _auth.signOut();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Access denied. You are not an authorized driver.")),
            );
            setState(() => _loading = false);
            return;
          }
        }

        // Step 2: Store user info in Firestore
        DocumentReference userRef = _firestore.collection('users').doc(user.uid);
        DocumentSnapshot doc = await userRef.get();

        String? studentId = _isDriver ? null : "STU-${user.uid.substring(0, 6)}";
        if (!_isDriver && studentId != null) {
          await _saveStudentFCMToken(studentId);
        }

        if (!doc.exists) {
          if (!_isDriver && studentId != null) {
            await _saveStudentToRealtimeDB(user.uid, phone);
          }
          await userRef.set({
            'uid': user.uid,
            'phone': phone,
            'role': _isDriver ? "Driver" : "Student",
            'studentId': studentId,
          });
        } else {
          await userRef.update({'role': _isDriver ? "Driver" : "Student"});
        }

        // Step 3: Navigate to Landing Page
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => LandingPage(user: user)),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Invalid OTP")),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveStudentToRealtimeDB(String uid, String phoneNumber) async {
    final fcmToken = await FirebaseMessaging.instance.getToken();
    final studentData = {
      "name": "STU-${uid.substring(0, 6)}",
      "phone": phoneNumber,
      "fcmToken": fcmToken,
    };

    DatabaseReference ref = FirebaseDatabase.instance.ref("students/$uid");
    await ref.set(studentData);

    print("Student info saved: UID = $uid, Token = $fcmToken");
  }
  Future<void> _saveStudentFCMToken(String studentId) async {
    String? token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await FirebaseDatabase.instance
          .ref('fcm_tokens/students/$studentId')
          .set(token);
    }
  }

  Widget _customTextField({
    required String label,
    required TextEditingController controller,
    required TextInputType inputType,
    IconData? icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            offset: Offset(2, 2),
            blurRadius: 6,
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: inputType,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon != null ? Icon(icon) : null,
          border: OutlineInputBorder(borderSide: BorderSide.none),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF141E30), Color(0xFF243B55)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: AnimatedContainer(
              duration: Duration(milliseconds: 300),
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(4, 4),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.security_rounded, size: 64, color: Colors.indigo),
                  const SizedBox(height: 20),
                  Text(
                    _otpSent ? "Enter OTP" : "Phone Login",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (!_otpSent) ...[
                    _customTextField(
                      label: "Phone Number",
                      controller: _phoneController,
                      inputType: TextInputType.phone,
                      icon: Icons.phone,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Login as Driver", style: TextStyle(fontSize: 16)),
                        Switch(
                          value: _isDriver,
                          onChanged: (value) => setState(() => _isDriver = value),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loading ? null : _sendOTP,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrangeAccent,
                        padding: EdgeInsets.symmetric(vertical: 14, horizontal: 40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _loading
                          ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                          : Text("Send OTP", style: TextStyle(fontSize: 16)),
                    ),
                  ] else ...[
                    Text(
                      "OTP sent to +91${_phoneController.text.trim()}",
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    _customTextField(
                      label: "Enter OTP",
                      controller: _otpController,
                      inputType: TextInputType.number,
                      icon: Icons.lock,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _loading ? null : _verifyOTP,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrangeAccent,
                        padding: EdgeInsets.symmetric(vertical: 14, horizontal: 40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _loading
                          ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                          : Text("Verify OTP", style: TextStyle(fontSize: 16)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
