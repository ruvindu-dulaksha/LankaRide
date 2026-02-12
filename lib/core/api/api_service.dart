import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_constants.dart';

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConstants.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  // Add interceptors for logging
  dio.interceptors.add(
    LogInterceptor(
      requestBody: true,
      responseBody: true,
      error: true,
      requestHeader: false,
      responseHeader: false,
    ),
  );

  // Add custom interceptor for debugging
  dio.interceptors.add(_CustomInterceptor());

  return dio;
});

class _CustomInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    debugPrint('🌐 API Request: ${options.method} ${options.path}');
    debugPrint('📍 URL: ${options.baseUrl}${options.path}');
    debugPrint('📤 Data: ${options.data}');
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    debugPrint('✅ API Response (${response.statusCode}): ${response.data}');
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    debugPrint('❌ API Error: ${err.message}');
    debugPrint('Error Type: ${err.type}');
    debugPrint('Status Code: ${err.response?.statusCode}');
    super.onError(err, handler);
  }
}

class ApiService {
  final Dio _dio;

  ApiService(this._dio);

  Future<PredictionResponse> predictRisk({
    required double latitude,
    required double longitude,
    required double rainLevel,
    required double unionDensity,
  }) async {
    try {
      debugPrint('\n🚀 Starting risk prediction...');
      debugPrint('📍 Location: ($latitude, $longitude)');
      debugPrint('☔ Rain Level: $rainLevel');
      debugPrint('🚗 Union Density: $unionDensity');

      final requestData = {
        'latitude': latitude,
        'longitude': longitude,
        'rain_level': rainLevel,
        'union_density': unionDensity,
      };

      debugPrint('📡 Sending request to backend...');
      final response = await _dio.post(
        AppConstants.predictEndpoint,
        data: requestData,
      );

      debugPrint('🎯 Backend response received');
      final predictionResponse = PredictionResponse.fromJson(response.data);

      debugPrint('✅ Prediction Result:');
      debugPrint('   Zone: ${predictionResponse.zone}');
      debugPrint('   Risk Score: ${predictionResponse.riskScore}');
      debugPrint('   Message: ${predictionResponse.message}');

      return predictionResponse;
    } on DioException catch (e) {
      debugPrint('\n❌ DioException occurred:');
      debugPrint('Type: ${e.type}');
      debugPrint('Message: ${e.message}');
      debugPrint('Status Code: ${e.response?.statusCode}');
      debugPrint('Response: ${e.response?.data}');

      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw ApiException(
          '⏱️ Connection timeout. Make sure the backend server is running on ${AppConstants.baseUrl}',
        );
      } else if (e.type == DioExceptionType.connectionError) {
        throw ApiException(
          'Cannot connect to server at ${AppConstants.baseUrl}. Make sure:\n'
          '1. Backend is running: python server.py\n'
          '2. Server is on port 5001\n'
          '3. Network connection is available',
        );
      } else if (e.response != null) {
        throw ApiException(
          e.response?.data['error'] ?? 'Server error occurred',
        );
      } else {
        throw ApiException('Network error. Please check your connection.');
      }
    } catch (e) {
      debugPrint('\n❌ Unexpected error: $e');
      throw ApiException('Unexpected error: $e');
    }
  }
}

final apiServiceProvider = Provider<ApiService>((ref) {
  final dio = ref.watch(dioProvider);
  return ApiService(dio);
});

class PredictionResponse {
  final String zone;
  final String message;
  final double riskScore;
  final Map<String, dynamic>? metadata;

  PredictionResponse({
    required this.zone,
    required this.message,
    required this.riskScore,
    this.metadata,
  });

  factory PredictionResponse.fromJson(Map<String, dynamic> json) {
    return PredictionResponse(
      zone: json['zone'] as String,
      message: json['message'] as String,
      riskScore: (json['risk_score'] as num).toDouble(),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  bool get isRedZone => zone.toLowerCase() == 'red';
  bool get isYellowZone => zone.toLowerCase() == 'yellow';
  bool get isGreenZone => zone.toLowerCase() == 'green';
}

class ApiException implements Exception {
  final String message;

  ApiException(this.message);

  @override
  String toString() => message;
}
