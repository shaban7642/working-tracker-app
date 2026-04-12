import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OtpInput extends StatefulWidget {
  final int length;
  final ValueChanged<String> onCompleted;
  final ValueChanged<String>? onChanged;
  final bool hasError;

  const OtpInput({
    super.key,
    this.length = 6,
    required this.onCompleted,
    this.onChanged,
    this.hasError = false,
  });

  @override
  OtpInputState createState() => OtpInputState();
}

class OtpInputState extends State<OtpInput> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    final limitedDigits =
        digits.length > widget.length ? digits.substring(0, widget.length) : digits;

    if (value != limitedDigits) {
      _controller.text = limitedDigits;
      _controller.selection = TextSelection.collapsed(offset: limitedDigits.length);
    }

    setState(() {});

    if (widget.onChanged != null) {
      widget.onChanged!(limitedDigits);
    }

    if (limitedDigits.length == widget.length) {
      widget.onCompleted(limitedDigits);
      _focusNode.unfocus();
    }
  }

  void clearCode() {
    _controller.clear();
    setState(() {});
    if (mounted) {
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _controller.text;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _focusNode.requestFocus(),
      child: Stack(
        children: [
          // Visual digit boxes
          IgnorePointer(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(
                widget.length,
                (index) {
                  final hasDigit = index < code.length;
                  final digit = hasDigit ? code[index] : '';
                  final isFocused = _focusNode.hasFocus && index == code.length;

                  return Expanded(
                    child: Container(
                      margin: EdgeInsets.only(right: index < widget.length - 1 ? 8 : 0),
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: widget.hasError
                              ? Colors.red
                              : isFocused
                                  ? Colors.white
                                  : const Color(0xFF2F3234),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          digit,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w500,
                            color: widget.hasError ? Colors.red : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          // Hidden text field for keyboard input
          Opacity(
            opacity: 0,
            child: SizedBox(
              height: 56,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                keyboardType: TextInputType.number,
                maxLength: widget.length,
                autofocus: true,
                decoration: const InputDecoration(
                  counterText: '',
                  border: InputBorder.none,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(widget.length),
                ],
                onChanged: _onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
