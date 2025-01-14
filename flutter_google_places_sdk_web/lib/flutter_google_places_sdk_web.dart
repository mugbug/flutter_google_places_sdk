@JS()
library places;

import 'dart:async';
import 'dart:developer';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_google_places_sdk_platform_interface/flutter_google_places_sdk_platform_interface.dart';
import 'package:flutter_google_places_sdk_web/types/autocomplete_response_web.dart';
import 'package:flutter_google_places_sdk_web/types/autocomplete_service.dart';
import 'package:flutter_google_places_sdk_web/types/autocomplete_session_token.dart';
import 'package:flutter_google_places_sdk_web/types/autocompletion_request.dart';
import 'package:flutter_google_places_sdk_web/types/map.dart' as map;
import 'package:flutter_google_places_sdk_web/types/place_details_request.dart';
import 'package:flutter_google_places_sdk_web/types/places_service.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:js/js.dart';
import 'package:js/js_util.dart';

@JS('initMap')
external set _initMap(void Function() f);

/// Web implementation plugin for flutter google places sdk
class FlutterGooglePlacesSdkWebPlugin extends FlutterGooglePlacesSdkPlatform {
  /// Register the plugin with the web implementation.
  /// Called by ?? when ??
  static void registerWith(Registrar registrar) {
    FlutterGooglePlacesSdkPlatform.instance = FlutterGooglePlacesSdkWebPlugin();
  }

  static const _SCRIPT_ID = 'flutter_google_places_sdk_web_script_id';

  Completer? _completer;

  AutocompleteService? _svcAutoComplete;
  PlacesService? _svcPlaces;
  AutocompleteSessionToken? _lastSessionToken;

  // Cache for photos
  final _photosCache = <String, PlaceWebPhoto>{};
  var _runningUid = 1;

  @override
  Future<void> deinitialize() async {
    // Nothing to do; there is no de-initialize for web
  }

  @override
  Future<void> initialize(String apiKey, {Locale? locale}) async {
    if (_svcAutoComplete != null) {
      return;
    }

    final completer = Completer();
    _completer = completer;

    _initMap = allowInterop(_doInit);

    html.Element? scriptExist =
        html.window.document.querySelector('#$_SCRIPT_ID');
    if (scriptExist != null) {
      _doInit();
    } else {
      final body = html.window.document.querySelector('body')!;
      body.append(html.ScriptElement()
        ..id = _SCRIPT_ID
        ..src =
            'https://maps.googleapis.com/maps/api/js?key=${apiKey}&libraries=places&callback=initMap'
        ..async = true
        ..type = 'application/javascript');
    }

    return completer.future.then((_) {});
  }

  void _doInit() {
    _svcAutoComplete = AutocompleteService();
    _svcPlaces = PlacesService(html.window.document.createElement('div'));
    _completer!.complete();
  }

  @override
  Future<bool?> isInitialized() async {
    return _completer?.isCompleted == true;
  }

  @override
  Future<FindAutocompletePredictionsResponse> findAutocompletePredictions(
    String query, {
    List<String>? countries,
    PlaceTypeFilter placeTypeFilter = PlaceTypeFilter.ALL,
    bool? newSessionToken,
    LatLng? origin,
    LatLngBounds? locationBias,
    LatLngBounds? locationRestriction,
  }) async {
    await _completer;
    final typeFilterStr = _placeTypeToStr(placeTypeFilter);
    if (locationRestriction != null) {
      // https://issuetracker.google.com/issues/36219203
      log("locationRestriction is not supported: https://issuetracker.google.com/issues/36219203");
    }
    final prom = _svcAutoComplete!.getPlacePredictions(
      AutocompletionRequest(
          input: query,
          types: typeFilterStr == null ? null : [typeFilterStr],
          componentRestrictions: ComponentRestrictions(country: countries),
          bounds: _boundsToWeb(locationBias)),
    );
    final resp = (await promiseToFuture(prom)) as AutocompleteResponse?;
    if (resp == null) {
      return FindAutocompletePredictionsResponse([]);
    }

    final predictions =
        resp.predictions.map(_translatePrediction).toList(growable: false);
    return FindAutocompletePredictionsResponse(predictions);
  }

  String? _placeTypeToStr(PlaceTypeFilter placeTypeFilter) {
    switch (placeTypeFilter) {
      case PlaceTypeFilter.ADDRESS:
        return "address";
      case PlaceTypeFilter.CITIES:
        return "(cities)";
      case PlaceTypeFilter.ESTABLISHMENT:
        return "establishment";
      case PlaceTypeFilter.GEOCODE:
        return "geocode";
      case PlaceTypeFilter.REGIONS:
        return "(regions)";
      case PlaceTypeFilter.ALL:
        return null;
    }
  }

  AutocompletePrediction _translatePrediction(
      AutocompletePredictionWeb prediction) {
    var main_text = prediction.structured_formatting.main_text;
    var secondary_text = prediction.structured_formatting.secondary_text;
    return AutocompletePrediction(
      distanceMeters: prediction.distance_meters,
      placeId: prediction.place_id,
      primaryText: main_text,
      secondaryText: secondary_text,
      fullText: '$main_text, $secondary_text',
    );
  }

  @override
  Future<FetchPlaceResponse> fetchPlace(
    String placeId, {
    List<PlaceField>? fields,
    bool? newSessionToken,
  }) async {
    final prom = _getDetails(PlaceDetailsRequest(
      placeId: placeId,
      fields: fields?.map(this._mapField).toList(growable: false),
      sessionToken: _lastSessionToken,
    ));

    final resp = await prom;
    return FetchPlaceResponse(resp.place);
  }

  String _mapField(PlaceField field) {
    switch (field) {
      case PlaceField.Address:
        return 'adr_address';
      case PlaceField.AddressComponents:
        return 'address_components';
      case PlaceField.BusinessStatus:
        return 'business_status';
      case PlaceField.Id:
        return 'place_id';
      case PlaceField.Location:
        return 'geometry.location';
      case PlaceField.Name:
        return 'name';
      case PlaceField.OpeningHours:
        return 'opening_hours';
      case PlaceField.PhoneNumber:
        return 'international_phone_number';
      case PlaceField.PhotoMetadatas:
        return 'photos';
      case PlaceField.PlusCode:
        return 'plus_code';
      case PlaceField.PriceLevel:
        return 'price_level';
      case PlaceField.Rating:
        return 'rating'; // not done yet
      case PlaceField.Types:
        return 'types';
      case PlaceField.UserRatingsTotal:
        return 'user_ratings_total';
      case PlaceField.UTCOffset:
        return 'utc_offset_minutes';
      case PlaceField.Viewport:
        return 'geometry.viewport';
      case PlaceField.WebsiteUri:
        return 'website';
      default:
        throw ArgumentError('Unsupported place field: $this');
    }
  }

  Future<_GetDetailsResponse> _getDetails(PlaceDetailsRequest request) {
    final completer = Completer<_GetDetailsResponse>();

    final GetDetailsCallback func = (place, status) {
      completer.complete(_GetDetailsResponse(_parsePlace(place), status));
    };

    final interop = allowInterop(func);
    _svcPlaces!.getDetails(request, interop);

    return completer.future;
  }

  Place? _parsePlace(PlaceWebResult? place) {
    if (place == null) {
      return null;
    }

    return Place(
      address: place.adr_address,
      addressComponents: place.address_components
          ?.map(_parseAddressComponent)
          .cast<AddressComponent>()
          .toList(growable: false),
      businessStatus: _parseBusinessStatus(place.business_status),
      attributions: place.html_attributions?.cast<String>(),
      latLng: _parseLatLang(place.geometry?.location),
      name: place.name,
      openingHours: _parseOpeningHours(place.opening_hours),
      phoneNumber: place.international_phone_number,
      photoMetadatas: place.photos
          ?.map((photo) => _parsePhotoMetadata(photo))
          .cast<PhotoMetadata>()
          .toList(growable: false),
      plusCode: _parsePlusCode(place.plus_code),
      priceLevel: place.price_level,
      rating: place.rating,
      types: place.types
          ?.map(_parsePlaceType)
          .where((item) => item != null)
          .cast<PlaceType>()
          .toList(growable: false),
      userRatingsTotal: place.user_ratings_total,
      utcOffsetMinutes: place.utc_offset_minutes,
      viewport: _parseLatLngBounds(place.geometry?.viewport),
      websiteUri: place.website == null ? null : Uri.parse(place.website!),
    );
  }

  PlaceType? _parsePlaceType(String? placeType) {
    if (placeType == null) {
      return null;
    }

    placeType = placeType.toUpperCase();
    return PlaceType.values.cast<PlaceType?>().firstWhere(
        (element) => element!.value == placeType,
        orElse: () => null);
  }

  AddressComponent? _parseAddressComponent(
      PlaceWebAddressComponent? addressComponent) {
    if (addressComponent == null) {
      return null;
    }

    return AddressComponent(
      name: addressComponent.long_name,
      shortName: addressComponent.short_name,
      types: addressComponent.types
          .map((e) => e.toString())
          .cast<String>()
          .toList(growable: false),
    );
  }

  LatLng? _parseLatLang(PlaceWebLatLng? location) {
    if (location == null) {
      return null;
    }

    return LatLng(
      lat: location.lat(),
      lng: location.lng(),
    );
  }

  PhotoMetadata? _parsePhotoMetadata(PlaceWebPhoto? photo) {
    if (photo == null) {
      return null;
    }

    final htmlAttrs = photo.html_attributions ?? [];
    final photoMetadata = PhotoMetadata(
        photoReference: _getPhotoMetadataReference(photo),
        width: photo.width,
        height: photo.height,
        attributions: htmlAttrs.length == 1 ? htmlAttrs[0] : null);

    _photosCache[photoMetadata.photoReference] = photo;

    return photoMetadata;
  }

  String _getPhotoMetadataReference(PlaceWebPhoto photo) {
    final num = _runningUid++;
    return "id_${num.toString()}";
  }

  LatLngBounds? _parseLatLngBounds(PlaceWebViewport? viewport) {
    if (viewport == null) {
      return null;
    }

    return LatLngBounds(
        southwest: _parseLatLang(viewport.getSouthWest())!,
        northeast: _parseLatLang(viewport.getNorthEast())!);
  }

  PlusCode? _parsePlusCode(PlaceWebPlusCode? plusCode) {
    if (plusCode == null) {
      return null;
    }

    return PlusCode(
        compoundCode: plusCode.compound_code, globalCode: plusCode.global_code);
  }

  BusinessStatus? _parseBusinessStatus(String? businessStatus) {
    if (businessStatus == null) {
      return null;
    }

    businessStatus = businessStatus.toUpperCase();
    return BusinessStatus.values.cast<BusinessStatus?>().firstWhere(
        (element) => element!.value == businessStatus,
        orElse: () => null);
  }

  OpeningHours? _parseOpeningHours(PlaceWebOpeningHours? openingHours) {
    if (openingHours == null) {
      return null;
    }

    return OpeningHours(
        periods: openingHours.periods
            .map(_parsePeriod)
            .cast<Period>()
            .toList(growable: false),
        weekdayText:
            openingHours.weekday_text.cast<String>().toList(growable: false));
  }

  Period _parsePeriod(PlaceWebPeriod period) {
    return Period(
        open: _parseTimeOfWeek(period.open),
        close: _parseTimeOfWeek(period.close));
  }

  TimeOfWeek? _parseTimeOfWeek(PlaceWebTimeOfWeek? timeOfWeek) {
    if (timeOfWeek == null) {
      return null;
    }

    return TimeOfWeek(
      day: _parseDayOfWeek(timeOfWeek.day),
      time:
          PlaceLocalTime(hours: timeOfWeek.hours, minutes: timeOfWeek.minutes),
    );
  }

  DayOfWeek _parseDayOfWeek(int day) {
    return DayOfWeek.values[day];
  }

  map.LatLngBounds? _boundsToWeb(LatLngBounds? bounds) {
    if (bounds == null) {
      return null;
    }
    return map.LatLngBounds(
        _latLngToWeb(bounds.southwest), _latLngToWeb(bounds.northeast));
  }

  map.LatLng _latLngToWeb(LatLng latLng) {
    return map.LatLng(latLng.lat, latLng.lng);
  }

  @override
  Future<FetchPlacePhotoResponse> fetchPlacePhoto(
    PhotoMetadata photoMetadata, {
    int? maxWidth,
    int? maxHeight,
  }) async {
    final value = _photosCache[photoMetadata.photoReference];
    if (value == null) {
      throw PlatformException(
        code: 'API_ERROR_PHOTO',
        message: 'PhotoMetadata must be initially fetched with fetchPlace',
        details: '',
      );
    }

    final url =
        value.getUrl(PhotoWebOptions(maxWidth: maxWidth, maxHeight: maxHeight));

    return FetchPlacePhotoResponse.imageUrl(url);
  }
}

/// A Place details response returned from PlacesService
class _GetDetailsResponse {
  /// Construct a new response
  const _GetDetailsResponse(this.place, this.status);

  /// The place of the response.
  final Place? place;

  /// The status of the response.
  final String status;
}
