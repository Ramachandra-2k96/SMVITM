import 'dart:convert';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:twilio_flutter/twilio_flutter.dart';

class FileSelector extends StatefulWidget {
  @override
  _FileSelectorState createState() => _FileSelectorState();
}

class _FileSelectorState extends State<FileSelector> with SingleTickerProviderStateMixin {
  Directory? _selectedDirectory;
  List<Map<String, String>> _files = [];
  late AnimationController _animationController;
  late Animation<double> _animation;
  late TwilioFlutter twilioFlutter;

  final String accountSid = 'ACa1b70d02af87bbb5050e218b755b0f5f';
  final String authToken = '52eb4a43ade069c2fb6c92a3a9ed2706';
  final String fromNumber = 'whatsapp:+14155238886';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    // Initialize Twilio client with your credentials
    twilioFlutter = TwilioFlutter(
      accountSid: accountSid,
      authToken: authToken,
      twilioNumber: fromNumber,
    );
  }

  Future<void> _pickFolder() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      setState(() {
        _selectedDirectory = Directory(selectedDirectory);
        _files = _selectedDirectory!.listSync()
            .where((file) => file.path.endsWith('.pdf'))
            .map((file) {
          String fileName = file.path.split(Platform.pathSeparator).last;
          String? mobileNumber = _extractMobileNumber(fileName);
          return {
            'fileName': fileName,
            'mobileNumber': mobileNumber ?? 'N/A'
          };
        }).toList();
        _animationController.forward();
        _uploadAndSendFiles();
      });
    }
  }

  String? _extractMobileNumber(String fileName) {
    RegExp regex = RegExp(r'(\d{10})(?=\.pdf$)');
    Match? match = regex.firstMatch(fileName);
    return match?.group(1);
  }

  Future<void> _uploadAndSendFiles() async {
    for (var file in _files) {
      String filePath = '${_selectedDirectory!.path}${Platform.pathSeparator}${file['fileName']!}';
      String mobileNumber = file['mobileNumber']!;
      if (mobileNumber != 'N/A') {
        setState(() {
          file['status'] = 'Uploading...';
        });
        String downloadUrl = await _uploadFileToFirebase(filePath, file['fileName']!);
        await _sendPDFViaWhatsApp(downloadUrl, mobileNumber);
        setState(() {
          file['status'] = 'Sent';
        });
      }
    }
  }

  Future<String> _uploadFileToFirebase(String filePath, String fileName) async {
    File file = File(filePath);
    try {
      TaskSnapshot snapshot = await FirebaseStorage.instance
          .ref('uploads/$fileName')
          .putFile(file);
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      print('Failed to upload file: $e');
      return '';
    }
  }

  Future<void> _sendPDFViaWhatsApp(String mediaUrl, String mobileNumber) async {
    final String toNumber = 'whatsapp:$mobileNumber';

    final response = await http.post(
      Uri.parse('https://api.twilio.com/2010-04-01/Accounts/$accountSid/Messages.json'),
      headers: {
        'Authorization': 'Basic ${base64Encode(utf8.encode('$accountSid:$authToken'))}',
      },
      body: {
        'To': toNumber,
        'From': fromNumber,
        'Body': 'Sending PDF file via WhatsApp!',
        'MediaUrl': mediaUrl,
      },
    );

    if (response.statusCode == 201) {
      print('PDF sent successfully');
    } else {
      print('Failed to send PDF: ${response.body}');
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('File Selector', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.deepPurple,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: _pickFolder,
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white, backgroundColor: Colors.deepPurple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30.0),
                ),
                padding: EdgeInsets.symmetric(vertical: 16.0, horizontal: 32.0),
              ),
              child: Text(
                'Select Folder',
                style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Expanded(
            child: _selectedDirectory == null
                ? Center(child: Text('No folder selected', style: TextStyle(fontSize: 18.0)))
                : FadeTransition(
              opacity: _animation,
              child: ListView.builder(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                itemCount: _files.length,
                itemBuilder: (context, index) {
                  var file = _files[index];
                  return Card(
                    elevation: 5,
                    margin: EdgeInsets.symmetric(vertical: 8.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15.0),
                    ),
                    child: ListTile(
                      leading: Icon(
                        Icons.picture_as_pdf,
                        color: Colors.deepPurple,
                      ),
                      title: Text(
                        file['fileName']!,
                        style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'Mobile Number: ${file['mobileNumber']}\nStatus: ${file['status'] ?? 'Pending'}',
                        style: TextStyle(fontSize: 14.0),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
