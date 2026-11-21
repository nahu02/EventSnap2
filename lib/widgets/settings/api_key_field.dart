import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/ai_provider.dart';

/// Obscured API key input with show/hide and paste buttons.
///
/// Owns its text controller, initialised from [initialValue]; give it a
/// `ValueKey(provider)` so switching providers starts from that provider's
/// stored key. Values passed to [onChanged] are trimmed.
class ApiKeyField extends StatefulWidget {
  const ApiKeyField({
    super.key,
    required this.provider,
    required this.initialValue,
    required this.onChanged,
    this.onCommit,
  });

  final AiProvider provider;
  final String initialValue;

  /// Called on every edit with the trimmed key.
  final ValueChanged<String> onChanged;

  /// Called when editing is finished: submit, focus lost or paste.
  final VoidCallback? onCommit;

  @override
  State<ApiKeyField> createState() => _ApiKeyFieldState();
}

class _ApiKeyFieldState extends State<ApiKeyField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  final FocusNode _focusNode = FocusNode();
  bool _obscured = true;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) widget.onCommit?.call();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('The clipboard is empty'),
        ),
      );
      return;
    }
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    widget.onChanged(text);
    widget.onCommit?.call();
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      obscureText: _obscured,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.done,
      onChanged: (value) => widget.onChanged(value.trim()),
      onSubmitted: (_) => widget.onCommit?.call(),
      decoration: InputDecoration(
        labelText: '${provider.displayName} API key',
        hintText: provider.apiKeyHint,
        helperText: 'Saved automatically and stored securely on this device',
        helperMaxLines: 3,
        prefixIcon: const Icon(Icons.key_outlined),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.content_paste),
              tooltip: 'Paste',
              onPressed: _paste,
            ),
            IconButton(
              icon: Icon(
                _obscured
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              tooltip: _obscured ? 'Show API key' : 'Hide API key',
              onPressed: () => setState(() => _obscured = !_obscured),
            ),
          ],
        ),
      ),
    );
  }
}
