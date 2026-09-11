import 'dart:math' as math;

import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_button.dart';
import '../../shared/widgets/voryn_card.dart';
import '../../shared/widgets/voryn_text_input.dart';
import '../profile/voryn_profile_service.dart';

class OnboardingData {
  String? userId;
  String fullName = '';
  String email = '';
  bool emailVerified = false;
  String countryCode = '+91';
  String countryIsoCode = 'IN';
  String phone = '';
  bool phoneVerified = false;
  bool avatarSelected = false;
  String vorynId = '';

  void prepareFromUser(User? user) {
    if (user == null) {
      _reset();
      return;
    }
    if (userId == user.id) return;
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    userId = user.id;
    fullName = (metadata['full_name'] ?? metadata['name'] ?? '').toString();
    email = user.email ?? '';
    emailVerified = user.emailConfirmedAt != null;
    phone = user.phone ?? '';
    countryCode = '+91';
    countryIsoCode = 'IN';
    phoneVerified = false;
    avatarSelected = false;
    vorynId = '';
  }

  void _reset() {
    userId = null;
    fullName = '';
    email = '';
    emailVerified = false;
    countryCode = '+91';
    countryIsoCode = 'IN';
    phone = '';
    phoneVerified = false;
    avatarSelected = false;
    vorynId = '';
  }

  String get initials {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .toList();
    if (parts.isEmpty) return '?';
    return parts.map((part) => part[0].toUpperCase()).join();
  }

  String get e164Phone {
    final localNumber = phone
        .replaceAll(RegExp(r'\D'), '')
        .replaceFirst(RegExp(r'^0+'), '');
    return '$countryCode$localNumber';
  }
}

final onboardingData = OnboardingData();

class OnboardingShell extends StatelessWidget {
  const OnboardingShell({
    super.key,
    required this.step,
    required this.child,
    this.dismissKeyboardOnTap = true,
  });

  final int step;
  final Widget child;
  final bool dismissKeyboardOnTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final spacing = context.vorynSpacing;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: GestureDetector(
          onTap: dismissKeyboardOnTap ? FocusScope.of(context).unfocus : null,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                spacing.screen,
                spacing.sm,
                spacing.screen,
                spacing.lg,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: math.max(
                    0,
                    constraints.maxHeight - spacing.sm - spacing.lg,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Semantics(
                          button: true,
                          label: 'Back',
                          child: IconButton(
                            tooltip: 'Back',
                            onPressed: () => context.pop(),
                            icon: const Icon(Icons.arrow_back_ios_new_rounded),
                          ),
                        ),
                        Text(
                          'Step $step of 3',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: colors.textMuted),
                        ),
                      ],
                    ),
                    SizedBox(height: spacing.lg),
                    child,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  String? _nameError;
  String? _phoneError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    onboardingData.prepareFromUser(const VorynProfileService().currentUser);
    _name = TextEditingController(text: onboardingData.fullName);
    _email = TextEditingController(text: onboardingData.email);
    _phone = TextEditingController(text: onboardingData.phone);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final name = _name.text.trim();
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    setState(() {
      _nameError = name.isEmpty ? 'Enter your full name' : null;
      _phoneError = digits.isEmpty
          ? 'Enter your phone number'
          : digits.length < 7
          ? 'Enter a valid phone number'
          : null;
    });
    if (_nameError != null || _phoneError != null) return;

    onboardingData.fullName = name;
    onboardingData.phone = _phone.text.trim();
    setState(() => _saving = true);
    final error = await const VorynProfileService().savePhone(
      fullName: onboardingData.fullName,
      phone: onboardingData.e164Phone,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _phoneError = error;
      });
      return;
    }
    setState(() => _saving = false);
    context.push('/onboarding/voryn-id');
  }

  void _selectCountry() {
    final colors = context.vorynColors;
    showCountryPicker(
      context: context,
      showPhoneCode: true,
      favorite: const ['IN'],
      countryListTheme: CountryListThemeData(
        backgroundColor: colors.backgroundSoft,
        textStyle: Theme.of(context).textTheme.bodyMedium,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        inputDecoration: InputDecoration(
          labelText: 'Search countries',
          hintText: 'Country or calling code',
          prefixIcon: const Icon(Icons.search_rounded),
          border: OutlineInputBorder(
            borderSide: BorderSide(color: colors.border),
          ),
        ),
      ),
      onSelect: (country) {
        setState(() {
          onboardingData.countryCode = '+${country.phoneCode}';
          onboardingData.countryIsoCode = country.countryCode;
          _phoneError = null;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;
    final colors = context.vorynColors;
    return OnboardingShell(
      step: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Complete your profile',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          SizedBox(height: spacing.sm),
          Text(
            'Help people recognize you on Voryn.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          SizedBox(height: spacing.xl),
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: colors.accentSoft,
                  child: onboardingData.avatarSelected
                      ? const Icon(Icons.person, size: 42)
                      : Text(
                          onboardingData.initials,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(color: colors.accent),
                        ),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: IconButton.filled(
                    tooltip: 'Choose profile photo',
                    onPressed: () => setState(
                      () => onboardingData.avatarSelected =
                          !onboardingData.avatarSelected,
                    ),
                    icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: spacing.xl),
          VorynTextInput(
            label: 'Full name',
            controller: _name,
            prefixIcon: Icons.person_outline_rounded,
            errorText: _nameError,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() => _nameError = null),
          ),
          SizedBox(height: spacing.md),
          VorynTextInput(
            label: 'Email',
            controller: _email,
            enabled: false,
            prefixIcon: Icons.alternate_email_rounded,
            suffixIcon: onboardingData.emailVerified
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: colors.success, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'Verified',
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(color: colors.success),
                      ),
                      const SizedBox(width: 12),
                    ],
                  )
                : null,
          ),
          SizedBox(height: spacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 124,
                child: Semantics(
                  button: true,
                  label: 'Choose country calling code',
                  child: InkWell(
                    onTap: _saving ? null : _selectCountry,
                    borderRadius: BorderRadius.circular(8),
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Country'),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${onboardingData.countryIsoCode} ${onboardingData.countryCode}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down_rounded),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: VorynTextInput(
                  label: 'Phone number',
                  controller: _phone,
                  prefixIcon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  enabled: !_saving,
                  errorText: _phoneError,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() => _phoneError = null),
                  onSubmitted: (_) => _continue(),
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.xxl),
          VorynButton.primary(
            label: 'Continue',
            isLoading: _saving,
            onPressed: _saving ? null : _continue,
          ),
        ],
      ),
    );
  }
}

class CreateVorynIdScreen extends StatefulWidget {
  const CreateVorynIdScreen({super.key});

  @override
  State<CreateVorynIdScreen> createState() => _CreateVorynIdScreenState();
}

class _CreateVorynIdScreenState extends State<CreateVorynIdScreen> {
  final _profileService = const VorynProfileService();
  final _username = TextEditingController();
  String? _state;
  bool _checking = false;
  bool _creating = false;
  String? _serviceError;
  static const _taken = {'rahul', 'admin', 'support', 'voryn', 'test'};

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  void _handleChanged(String value) {
    setState(() {
      _state = null;
      _serviceError = null;
    });
  }

  Future<void> _checkAvailability() async {
    final normalized = _normalizedId;
    final validationError = _validationError(normalized);
    if (validationError != null) {
      setState(() {
        _state = 'invalid';
        _serviceError = null;
      });
      return;
    }
    if (_taken.contains(normalized)) {
      setState(() => _state = 'taken');
      return;
    }

    setState(() {
      _checking = true;
      _state = null;
      _serviceError = null;
    });
    final checkedId = normalized;
    final result = await _profileService.checkVorynIdAvailability(checkedId);
    if (!mounted || checkedId != _normalizedId) return;
    setState(() {
      _checking = false;
      _serviceError = result.error;
      _state = result.error != null
          ? 'error'
          : result.isAvailable == true
          ? 'available'
          : 'taken';
    });
  }

  Future<void> _createVorynId() async {
    final normalized = _normalizedId;
    if (_state != 'available') return;
    setState(() {
      _creating = true;
      _serviceError = null;
    });
    final error = await _profileService.claimVorynId(normalized);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _creating = false;
        _state = 'error';
        _serviceError = error;
      });
      return;
    }
    onboardingData.vorynId = normalized;
    context.go('/connect');
  }

  String get _normalizedId =>
      _username.text.trim().replaceFirst('@', '').toLowerCase();

  String? _validationError(String normalized) {
    if (normalized.length < 3) return 'Use at least 3 characters';
    if (normalized.length > 24) return 'Use 24 characters or fewer';
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(normalized)) {
      return 'Use letters, numbers and underscores only';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;
    final colors = context.vorynColors;
    final normalized = _normalizedId;
    final available = _state == 'available' && !_checking;
    final message = switch (_state) {
      'available' => '@$normalized is available',
      'taken' => 'This Voryn ID is already taken',
      'invalid' => _validationError(normalized) ?? 'Enter a valid Voryn ID.',
      'error' => _serviceError ?? 'Could not check this Voryn ID.',
      _ => 'Enter an ID, then check whether it is available.',
    };
    final messageColor = _state == 'available'
        ? colors.success
        : _state == null
        ? colors.textMuted
        : colors.danger;
    return OnboardingShell(
      step: 3,
      dismissKeyboardOnTap: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Create your Voryn ID',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          SizedBox(height: spacing.sm),
          Text(
            'This is how people can find and call you on Voryn.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          SizedBox(height: spacing.xl),
          Center(
            child: Icon(
              Icons.alternate_email_rounded,
              color: colors.accent,
              size: 42,
            ),
          ),
          SizedBox(height: spacing.xl),
          VorynTextInput(
            label: 'Voryn ID',
            controller: _username,
            hintText: 'vikash',
            prefixIcon: Icons.alternate_email_rounded,
            isLoading: _checking,
            enabled: !_creating,
            textInputAction: TextInputAction.search,
            onChanged: _handleChanged,
            onSubmitted: (_) => _checkAvailability(),
          ),
          SizedBox(height: spacing.md),
          VorynButton.secondary(
            label: 'Check availability',
            leadingIcon: Icons.search_rounded,
            isLoading: _checking,
            onPressed: _checking || _creating ? null : _checkAvailability,
          ),
          SizedBox(height: spacing.sm),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: Row(
              key: ValueKey(message),
              children: [
                Icon(
                  _state == 'available'
                      ? Icons.check_circle
                      : _state == null
                      ? Icons.info_outline
                      : Icons.error_outline,
                  color: messageColor,
                  size: 17,
                ),
                SizedBox(width: spacing.xs),
                Expanded(
                  child: Text(
                    _checking ? 'Checking...' : message,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: messageColor),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: spacing.lg),
          VorynSurface(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: colors.iconMuted, size: 18),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: Text(
                    'People can also find you using your verified phone or email.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: spacing.xxl),
          VorynButton.primary(
            label: 'Create Voryn ID',
            isLoading: _creating,
            onPressed: available && !_creating ? _createVorynId : null,
          ),
        ],
      ),
    );
  }
}
