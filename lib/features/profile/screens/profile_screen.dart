import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../drivers/providers/driver_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _vehicleColorController = TextEditingController();
  final _licensePlateController = TextEditingController();
  bool _isEditing = false;
  bool _isLoading = false;
  String? _message;
  File? _selectedImageFile;
  String? _savedPhotoPath;
  final _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _vehicleColorController.dispose();
    _licensePlateController.dispose();
    super.dispose();
  }

  void _loadUserData() async {
    final authService = ref.read(authServiceProvider);
    final user = authService.currentUser;
    if (user != null) {
      _nameController.text = user.displayName ?? '';
      _emailController.text = user.email ?? '';
      _phoneController.text = user.phoneNumber ?? '';

      // Load vehicle details from Firestore
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          final data = userDoc.data();
          if (data != null) {
            _vehicleColorController.text = data['vehicle_color'] ?? '';
            _licensePlateController.text = data['license_plate'] ?? '';
          }
        }
      } catch (e) {
        debugPrint('Error loading vehicle details: $e');
      }

      // Load saved photo path
      _loadSavedPhoto();
    }
  }

  Future<void> _loadSavedPhoto() async {
    final authService = ref.read(authServiceProvider);
    final photoPath = await authService.getUserPhotoPath();
    if (mounted) {
      setState(() {
        _savedPhotoPath = photoPath;
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      debugPrint('📸 Opening image picker...');
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      if (pickedFile != null) {
        debugPrint('✅ Image picked successfully: ${pickedFile.path}');
        setState(() {
          _selectedImageFile = File(pickedFile.path);
          _message = null;
        });
      } else {
        debugPrint('⚠️ User cancelled image picker');
      }
    } catch (e) {
      debugPrint('❌ Error picking image: $e');
      setState(() {
        _message = 'Failed to pick image: ${e.toString()}';
      });
    }
  }

  Future<void> _updateProfile() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      final user = authService.currentUser;

      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Update Firebase Auth profile (name and photo)
      await authService.updateUserProfile(
        displayName: _nameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        photoFile: _selectedImageFile,
      );

      // Update Firestore with vehicle details
      final updates = <String, dynamic>{
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'last_updated': FieldValue.serverTimestamp(),
      };

      // Only update vehicle fields if they have values
      final vehicleColor = _vehicleColorController.text.trim();
      final licensePlate = _licensePlateController.text.trim();

      if (vehicleColor.isNotEmpty) {
        updates['vehicle_color'] = vehicleColor;
      }
      if (licensePlate.isNotEmpty) {
        updates['license_plate'] = licensePlate;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update(updates);

      // Reload saved photo path
      await _loadSavedPhoto();

      setState(() {
        _message = 'Profile updated successfully!';
        _isEditing = false;
        _selectedImageFile = null; // Clear selected image after upload
      });
    } catch (e) {
      setState(() {
        _message = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    final confirmSignOut = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(
          'Sign Out',
          style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
        ),
        content: Text(
          'Are you sure you want to sign out?',
          style: TextStyle(
            color: Theme.of(context).textTheme.bodyMedium?.color,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Sign Out',
              style: TextStyle(color: AppTheme.error),
            ),
          ),
        ],
      ),
    );

    if (confirmSignOut == true) {
      await ref.read(authServiceProvider).signOut();
      if (mounted) {
        context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDarkMode
                ? [
                    const Color(0xFF1A1B23),
                    const Color(0xFF0F1419),
                    const Color(0xFF1A1B23),
                  ]
                : [
                    const Color(0xFFF5F7FA),
                    const Color(0xFFFFFFFF),
                    const Color(0xFFF5F7FA),
                  ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),

                // Header
                Row(
                  children: [
                    IconButton(
                      onPressed: () => context.go('/map'),
                      icon: Icon(
                        Icons.arrow_back_ios,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Profile',
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              if (_isEditing) {
                                _updateProfile();
                              } else {
                                setState(() {
                                  _isEditing = true;
                                });
                              }
                            },
                      child: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.primary,
                              ),
                            )
                          : Text(
                              _isEditing ? 'Save' : 'Edit',
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ],
                ).animate().fadeIn(duration: 600.ms),

                const SizedBox(height: 40),

                // Profile Picture
                Center(
                      child: Stack(
                        children: [
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  AppTheme.primary.withOpacity(0.2),
                                  AppTheme.primary.withOpacity(0.05),
                                ],
                              ),
                              border: Border.all(
                                color: AppTheme.primary.withOpacity(0.3),
                                width: 3,
                              ),
                            ),
                            child: _selectedImageFile != null
                                ? ClipOval(
                                    child: Image.file(
                                      _selectedImageFile!,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : _savedPhotoPath != null &&
                                      File(_savedPhotoPath!).existsSync()
                                ? ClipOval(
                                    child: Image.file(
                                      File(_savedPhotoPath!),
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                            return _buildDefaultAvatar();
                                          },
                                    ),
                                  )
                                : _buildDefaultAvatar(),
                          ),
                          if (_isEditing)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: _pickImage,
                                  borderRadius: BorderRadius.circular(50),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                    .animate()
                    .fadeIn(delay: 200.ms)
                    .scale(
                      begin: const Offset(0.8, 0.8),
                      curve: Curves.elasticOut,
                    ),

                const SizedBox(height: 40),

                // Success/Error Message
                if (_message != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color:
                          (_message!.contains('success')
                                  ? AppTheme.accent
                                  : AppTheme.error)
                              .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            (_message!.contains('success')
                                    ? AppTheme.accent
                                    : AppTheme.error)
                                .withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _message!.contains('success')
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                          color: _message!.contains('success')
                              ? AppTheme.accent
                              : AppTheme.error,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _message!,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: _message!.contains('success')
                                      ? AppTheme.accent
                                      : AppTheme.error,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(),

                // Name Field
                _buildProfileField(
                  controller: _nameController,
                  label: 'Full Name',
                  icon: Icons.person_outline,
                  isEditable: _isEditing,
                  delay: 400,
                ),

                const SizedBox(height: 20),

                // Email Field (non-editable)
                _buildProfileField(
                  controller: _emailController,
                  label: 'Email Address',
                  icon: Icons.email_outlined,
                  isEditable: false,
                  delay: 500,
                ),

                const SizedBox(height: 20),

                // Phone Field
                _buildProfileField(
                  controller: _phoneController,
                  label: 'Phone Number',
                  icon: Icons.phone_outlined,
                  isEditable: _isEditing,
                  delay: 600,
                ),

                const SizedBox(height: 20),

                // Vehicle Color Field
                _buildProfileField(
                  controller: _vehicleColorController,
                  label: 'Vehicle Color',
                  icon: Icons.color_lens_outlined,
                  isEditable: _isEditing,
                  delay: 700,
                ),

                const SizedBox(height: 20),

                // License Plate Field
                _buildProfileField(
                  controller: _licensePlateController,
                  label: 'License Plate',
                  icon: Icons.badge_outlined,
                  isEditable: _isEditing,
                  delay: 800,
                ),

                const SizedBox(height: 40),

                // Profile Stats
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? Colors.white.withOpacity(0.05)
                        : Colors.black.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDarkMode
                          ? Colors.white.withOpacity(0.1)
                          : Colors.black.withOpacity(0.15),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Account Info',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Theme.of(context).textTheme.titleLarge?.color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Real-time stats from Firestore
                      StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(FirebaseAuth.instance.currentUser?.uid)
                            .snapshots(),
                        builder: (context, snapshot) {
                          String memberSince = 'New';
                          String? vehicleColor;
                          String? licensePlate;

                          if (snapshot.hasData && snapshot.data!.exists) {
                            final data =
                                snapshot.data!.data() as Map<String, dynamic>?;
                            if (data != null) {
                              // Member since
                              final createdAt =
                                  data['created_at'] as Timestamp?;
                              if (createdAt != null) {
                                final date = createdAt.toDate();
                                final months =
                                    DateTime.now().difference(date).inDays ~/
                                    30;
                                if (months < 1) {
                                  memberSince = 'New';
                                } else if (months < 12) {
                                  memberSince = '${months}mo';
                                } else {
                                  memberSince = '${months ~/ 12}yr';
                                }
                              }
                              final vColor = data['vehicle_color'];
                              final lPlate = data['license_plate'];

                              if (vColor != null &&
                                  vColor.toString().isNotEmpty &&
                                  vColor != 'TBD') {
                                vehicleColor = vColor.toString();
                              }
                              if (lPlate != null &&
                                  lPlate.toString().isNotEmpty &&
                                  lPlate != 'TBD') {
                                licensePlate = lPlate.toString();
                              }
                            }
                          }

                          // Build list of stat items dynamically
                          final statItems = <Widget>[
                            _buildStatItem(
                              'Member',
                              memberSince,
                              Icons.calendar_today_outlined,
                            ),
                          ];

                          if (vehicleColor != null) {
                            statItems.add(
                              _buildStatItem(
                                'Vehicle',
                                vehicleColor,
                                Icons.color_lens_outlined,
                              ),
                            );
                          }

                          if (licensePlate != null) {
                            statItems.add(
                              _buildStatItem(
                                'Plate',
                                licensePlate,
                                Icons.badge_outlined,
                              ),
                            );
                          }

                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: statItems,
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      // Online drivers count
                      Consumer(
                        builder: (context, ref, child) {
                          final onlineCount = ref.watch(
                            onlineDriversCountProvider,
                          );
                          return Row(
                            children: [
                              const Icon(
                                Icons.circle,
                                size: 10,
                                color: AppTheme.accent,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                onlineCount.when(
                                  data: (count) =>
                                      '$count driver${count == 1 ? '' : 's'} online now',
                                  loading: () => 'Checking online drivers...',
                                  error: (_, __) => 'Unable to check',
                                ),
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: isDarkMode
                                          ? Colors.white60
                                          : Colors.black54,
                                    ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 700.ms),

                const SizedBox(height: 40),

                // Settings Section
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? Colors.white.withOpacity(0.05)
                        : Colors.black.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDarkMode
                          ? Colors.white.withOpacity(0.1)
                          : Colors.black.withOpacity(0.15),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Settings',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Theme.of(context).textTheme.titleLarge?.color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Theme Toggle
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.brightness_6_outlined,
                                color: isDarkMode
                                    ? Colors.white.withOpacity(0.8)
                                    : Colors.black.withOpacity(0.8),
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Dark Mode',
                                    style: Theme.of(context).textTheme.bodyLarge
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).textTheme.bodyLarge?.color,
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                  Text(
                                    'Toggle dark/light theme',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: isDarkMode
                                              ? Colors.white60
                                              : Colors.black54,
                                          fontSize: 12,
                                        ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Switch(
                            value:
                                ref.watch(themeModeProvider) == ThemeMode.dark,
                            onChanged: (value) {
                              ref
                                  .read(themeModeProvider.notifier)
                                  .toggleTheme();
                            },
                            activeThumbColor: AppTheme.primary,
                            activeTrackColor: AppTheme.primary.withOpacity(0.5),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => context.push('/scenario-demos'),
                          icon: const Icon(Icons.play_circle_outline),
                          label: const Text('Open Scenario Demo Tests (A-D)'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primary,
                            side: BorderSide(
                              color: AppTheme.primary.withOpacity(0.45),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Quick emergency validation: open all Chapter 5 scenario demos with expected outputs.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isDarkMode ? Colors.white60 : Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 750.ms),

                const SizedBox(height: 40),

                // Sign Out Button
                if (!_isEditing)
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _signOut,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.error,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.logout, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Sign Out',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ).animate().fadeIn(delay: 800.ms),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultAvatar() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withOpacity(0.2),
            AppTheme.primary.withOpacity(0.05),
          ],
        ),
      ),
      child: const Icon(Icons.person, size: 60, color: AppTheme.primary),
    );
  }

  Widget _buildProfileField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isEditable,
    required int delay,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final hintColor = isDarkMode ? Colors.white60 : Colors.black54;
    final disabledColor = isDarkMode ? Colors.white38 : Colors.black38;
    final fillColor = isDarkMode
        ? Colors.white.withOpacity(isEditable ? 0.05 : 0.02)
        : Colors.black.withOpacity(isEditable ? 0.04 : 0.02);
    final borderColor = isDarkMode
        ? Colors.white.withOpacity(0.1)
        : Colors.black.withOpacity(0.15);

    return TextFormField(
      controller: controller,
      enabled: isEditable,
      style: TextStyle(color: isEditable ? textColor : hintColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: isEditable ? hintColor : disabledColor),
        filled: true,
        fillColor: fillColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: borderColor),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: borderColor.withOpacity(0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.primary),
        ),
        prefixIcon: Icon(icon, color: isEditable ? hintColor : disabledColor),
      ),
    ).animate().fadeIn(delay: delay.ms, duration: 600.ms).slideY(begin: 0.2);
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final valueColor = isDarkMode ? Colors.white : Colors.black87;
    final labelColor = isDarkMode ? Colors.white60 : Colors.black54;

    return Column(
      children: [
        Icon(icon, color: AppTheme.primary, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: valueColor,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: labelColor),
        ),
      ],
    );
  }
}
