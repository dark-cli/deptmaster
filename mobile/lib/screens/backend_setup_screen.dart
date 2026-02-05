import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../api.dart';
import '../widgets/gradient_background.dart';
import 'login_screen.dart';

class BackendSetupScreen extends StatefulWidget {
  const BackendSetupScreen({super.key});

  @override
  State<BackendSetupScreen> createState() => _BackendSetupScreenState();
}

class _BackendSetupScreenState extends State<BackendSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _successMessage;
  bool _testingConnection = false;
  bool _connectionTestPassed = false;
  String? _testedIp;
  int? _testedPort;

  @override
  void initState() {
    super.initState();
    _loadCurrentConfig();
    // Listen to text field changes to reset test status
    _ipController.addListener(_onFieldChanged);
    _portController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (_connectionTestPassed) {
      final currentIp = _ipController.text.trim();
      final currentPort = int.tryParse(_portController.text.trim());
      
      // Reset test status if IP or port changed
      if (currentIp != _testedIp || currentPort != _testedPort) {
        setState(() {
          _connectionTestPassed = false;
          _testedIp = null;
          _testedPort = null;
          _error = null;
          _successMessage = null;
        });
      }
    }
  }

  Future<void> _loadCurrentConfig() async {
    final ip = await Api.getBackendIp();
    final port = await Api.getBackendPort();
    setState(() {
      _ipController.text = ip;
      _portController.text = port.toString();
    });
  }

  @override
  void dispose() {
    _ipController.removeListener(_onFieldChanged);
    _portController.removeListener(_onFieldChanged);
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _testingConnection = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final ip = _ipController.text.trim();
      final port = int.parse(_portController.text.trim());
      
      // Test connection by trying to reach the health endpoint
      final testUrl = 'http://$ip:$port/health';
      
      final response = await http.get(
        Uri.parse(testUrl),
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('Connection timeout - server did not respond');
        },
      );

      if (mounted) {
        setState(() {
          _testingConnection = false;
        });
        
        if (response.statusCode == 200) {
          setState(() {
            _connectionTestPassed = true;
            _testedIp = ip;
            _testedPort = port;
            _error = null;
            _successMessage = 'Connection successful!';
          });
        } else {
          setState(() {
            _connectionTestPassed = false;
            _testedIp = null;
            _testedPort = null;
            _error = 'Server responded with status ${response.statusCode}';
            _successMessage = null;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        // Format error message
        final errorMessage = _formatConnectionError(e);
        setState(() {
          _testingConnection = false;
          _connectionTestPassed = false;
          _testedIp = null;
          _testedPort = null;
          _error = errorMessage;
          _successMessage = null;
        });
      }
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final ip = _ipController.text.trim();
      final port = int.parse(_portController.text.trim());
      
      await Api.setBackendConfig(ip, port);

      if (mounted) {
        // Navigate to login screen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        // Format error message
        final errorMessage = _formatConnectionError(e);
        setState(() {
          _loading = false;
          _error = errorMessage;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 32, // Account for padding
                  ),
                  child: IntrinsicHeight(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                        Icon(
                          Icons.settings_ethernet,
                          size: 64,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Configure Backend Server',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Enter your backend server IP address and port',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        TextFormField(
                          controller: _ipController,
                          decoration: InputDecoration(
                            labelText: 'Server IP',
                            hintText: 'e.g., 192.168.1.100 or localhost',
                            prefixIcon: const Icon(Icons.dns),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter server IP';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _portController,
                          decoration: InputDecoration(
                            labelText: 'Port',
                            hintText: 'e.g., 8000',
                            prefixIcon: const Icon(Icons.numbers),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          textInputAction: TextInputAction.done,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter port number';
                            }
                            final port = int.tryParse(value);
                            if (port == null || port < 1 || port > 65535) {
                              return 'Please enter a valid port (1-65535)';
                            }
                            return null;
                          },
                          onFieldSubmitted: (_) => _handleSubmit(),
                        ),
                        // Always reserve space for error/success message to prevent layout shifts
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 56, // Fixed height to reserve space (12px padding * 2 + icon height + text height)
                          child: _error != null
                              ? Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.errorContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        color: Theme.of(context).colorScheme.onErrorContainer,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _error!,
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.onErrorContainer,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : _successMessage != null
                                  ? Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.green,
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.check_circle_outline,
                                            color: Colors.green,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _successMessage!,
                                              style: const TextStyle(
                                                color: Colors.green,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : const SizedBox.shrink(), // Empty space when no message
                        ),
                        const SizedBox(height: 24),
                        // Stack buttons vertically on mobile
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OutlinedButton(
                              onPressed: _testingConnection || _loading ? null : _testConnection,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: BorderSide(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 2,
                                ),
                              ),
                              child: _testingConnection
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Text(
                                      'Test Connection',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: (_loading || !_connectionTestPassed) ? null : _handleSubmit,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                backgroundColor: _connectionTestPassed
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                                foregroundColor: _connectionTestPassed
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.38),
                              ),
                              child: _loading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : Text(
                                      'Save & Continue',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                            if (!_connectionTestPassed && !_testingConnection) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Please test connection first',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Note: For Android devices, use your computer\'s IP address instead of localhost',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                          textAlign: TextAlign.center,
                        ),
                ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String _formatConnectionError(dynamic error) {
    // Extract error code if available
    String? errorCode;
    String simpleMessage = 'Cannot connect to server';
    
    // Try to extract error code from error message
    try {
      if (error != null) {
        final errorStr = error.toString();
        // Extract errno from error message if present (e.g., "errno = 111")
        final errnoMatch = RegExp(r'errno\s*=\s*(\d+)').firstMatch(errorStr);
        if (errnoMatch != null) {
          errorCode = errnoMatch.group(1);
        }
      }
    } catch (_) {
      // Ignore if extraction fails
    }
    
    // Determine simple message based on error content
    final errorStr = error.toString().toLowerCase();
    
    if (error is TimeoutException) {
      simpleMessage = 'Connection timeout';
    } else if (errorStr.contains('connection refused')) {
      simpleMessage = 'Connection refused';
    } else if (errorStr.contains('failed host lookup') || errorStr.contains('name resolution')) {
      simpleMessage = 'Server not found';
    } else if (errorStr.contains('network is unreachable')) {
      simpleMessage = 'Network unreachable';
    } else if (errorStr.contains('timeout')) {
      simpleMessage = 'Connection timeout';
    } else {
      simpleMessage = 'Connection failed';
    }
    
    // Add error code if available
    if (errorCode != null) {
      return '$simpleMessage (Error: $errorCode)';
    }
    return simpleMessage;
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
  @override
  String toString() => message;
}
