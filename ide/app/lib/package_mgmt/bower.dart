// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

/**
 * Bower services.
 */

// TODO(ussuri): Add tests.

library spark.package_mgmt.bower;

import 'dart:async';
import 'dart:convert' show JSON;

import 'package:logging/logging.dart';

import 'package_manager.dart';
import 'bower_fetcher.dart';
import '../jobs.dart';
import '../workspace.dart';

Logger _logger = new Logger('spark.bower');

// TODO(ussuri): Make package-private once no longer used outside.
final BowerProperties bowerProperties = new BowerProperties();

class BowerProperties extends PackageServiceProperties {
  String get packageServiceName => 'bower';
  String get packageSpecFileName => 'bower.json';
  String get packagesDirName => 'bower_packages';

  // Bower doesn't use any of the below nullified properties/methods.

  String get libDirName => null;
  String get packageRefPrefix => null;
  RegExp get packageRefPrefixRegexp => null;

  void setSelfReference(Project project, String selfReference) {}
  String getSelfReference(Project project) => null;
}

class BowerManager extends PackageManager {
  BowerManager(Workspace workspace) : super(workspace);

  PackageServiceProperties get properties => bowerProperties;

  PackageBuilder getBuilder() => new _BowerBuilder();

  PackageResolver getResolverFor(Project project) =>
      new _BowerResolver._(project);

  Future installPackages(Project project) {
    final File specFile = project.getChild(properties.packageSpecFileName);

    // The client is expected to call us only when the project has bower.json.
    if (specFile == null) {
      throw new StateError('installPackages() called, but there is no bower.json');
    }

    return project.getOrCreateFolder(properties.packagesDirName, true)
        .then((Folder packagesDir) {
      final fetcher = new BowerFetcher(
          packagesDir.entry, properties.packageSpecFileName);

      return fetcher.fetchDependencies(specFile.entry).whenComplete(() {
        return project.refresh();
      }).catchError((e, st) {
        _logger.severe('Error getting Bower packages', e, st);
        return new Future.error(e, st);
      });
    });
  }

  Future upgradePackages(Project project) {
    return new Future.error('Not implemented');
  }
}

/**
 * A dummy class that currently doesn't resolve anything, since the definition
 * of a Bower package reference in JS code is yet unclear.
 */
class _BowerResolver extends PackageResolver {
  _BowerResolver._(Project project);

  PackageServiceProperties get properties => bowerProperties;

  File resolveRefToFile(String url) => null;

  String getReferenceFor(File file) => null;
}

/**
 * A [Builder] implementation which watches for changes to `bower.json` files
 * and updates the project Bower metadata.
 */
class _BowerBuilder extends PackageBuilder {
  _BowerBuilder();

  PackageServiceProperties get properties => bowerProperties;

  Future build(ResourceChangeEvent event, ProgressMonitor monitor) {
    List futures = [];

    for (ChangeDelta delta in event.changes) {
      Resource r = delta.resource;

      if (r.isDerived()) continue;

      if (r.name == properties.packageSpecFileName && r.parent is Project) {
        futures.add(_handlePackageSpecChange(delta));
      }
    }

    return Future.wait(futures);
  }

  Future _handlePackageSpecChange(ChangeDelta delta) {
    File file = delta.resource;

    if (delta.isDelete) {
      properties.setSelfReference(file.project, null);
      return new Future.value();
    } else {
      return file.getContents().then((String spec) {
        file.clearMarkers(properties.packageServiceName);

        try {
          properties.setSelfReference(
              file.project, _parsePackageNameFromSpec(spec));
        } on Exception catch (e) {
          file.createMarker(
              properties.packageServiceName, Marker.SEVERITY_ERROR, '${e}', 1);
        }
      });
    }
  }

  String _parsePackageNameFromSpec(String spec) {
    // TODO(ussuri): Similar code is now in 3 places in package_mgmt.
    // Generalize package spec parsing as a PackageServiceProperties API.
    Map<String, dynamic> specMap = JSON.decode(spec);
    return specMap == null ? null : specMap['name'];
  }
}
