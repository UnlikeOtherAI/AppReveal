import 'package:appreveal/appreveal.dart';
import 'package:flutter/material.dart';

import '../services/example_state_container.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> with ScreenIdentifiable {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;

  @override
  String get screenKey => 'profile.edit';

  @override
  String get screenTitle => 'Edit Profile';

  @override
  void initState() {
    super.initState();
    AppReveal.registerScreen(this);
    _nameController = TextEditingController(text: ExampleStateContainer.instance.userName);
    _emailController = TextEditingController(text: ExampleStateContainer.instance.userEmail);
  }

  void _save() {
    ExampleStateContainer.instance
      ..userName = _nameController.text
      ..userEmail = _emailController.text;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          TextButton(
            key: const ValueKey('edit_profile.save'),
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              key: const ValueKey('edit_profile.name'),
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('edit_profile.email'),
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }
}
