// @dart=2.11

import 'package:analyzer/analyzer.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:collection/collection.dart';
import 'package:source_gen/source_gen.dart';
import 'package:functional_data/functional_data.dart';

Builder functionalData(BuilderOptions options) => SharedPartBuilder([FunctionalDataGenerator()], 'functional_data');

class FunctionalDataGenerator extends GeneratorForAnnotation<FunctionalData> {
  @override
  Future<String> generateForAnnotatedElement(Element element, ConstantReader annotation, BuildStep buildStep) =>
      _generateDataType(element);
}

bool elementHasMetaAnnotation(Element e) => e.metadata.any(isSimpleDataAnnotation);

bool isSimpleDataAnnotation(ElementAnnotation a) =>
    a.computeConstantValue().type.getDisplayString(withNullability: false) == "FunctionalData";

class CustomEquality {
  final Equality equality;

  const CustomEquality(this.equality);
}

String _getCustomEquality(List<ElementAnnotation> annotations) {
  final annotation = annotations.firstWhere(
      (a) => a.computeConstantValue().type.getDisplayString(withNullability: false) == "CustomEquality",
      orElse: () => null);
  if (annotation != null) {
    final source = annotation.toSource();
    return source.substring("@CustomEquality(".length, source.length - 1).replaceAll('?', '');
  } else
    return null;
}

Future<String> _generateDataType(Element element) async {
  if (element is! ClassElement) throw Exception('FunctionalData annotation must only be used on classes');

  final resolvedLibrary = await element.session.getResolvedLibraryByElement(element.library);
  resolvedLibrary.getElementDeclaration(element).node;

  final className = element.name.replaceAll('\$', '');

  final classElement = element as ClassElement;

  final fields = classElement.fields.where((f) => !f.isSynthetic && !f.isStatic).map((f) {
    return Field(
      f.name,
      null,
      ((resolvedLibrary.getElementDeclaration(f).node as VariableDeclaration).parent as VariableDeclarationList)
          .type
          .toSource(),
      _getCustomEquality(f.metadata),
    );
  });

  final fieldDeclarations = fields.map((f) => '${f.type} get ${f.name};');
  final toString =
      '@override\nString toString() => "$className(${fields.map((f) => '${f.name}: \$${f.name}').join(', ')})";';
  final copyWith =
      '$className copyWith({${fields.map((f) => '${f.optionalType} ${f.name}').join(', ')}}) => $className(${fields.map((f) => '${f.name}: ${f.name} ?? this.${f.name}').join(', \n')});';

  final equality = '@override\nbool operator ==(Object other) => ${([
        'other is $className',
        'other.runtimeType == runtimeType'
      ] + fields.map((f) => '${_generateEquality(f)}').toList()).join(' && \n')};';

  final hash =
      '@override int get hashCode { var result = 17; ${fields.map((f) => 'result = 37 * result + ${_generateHash(f)};').join()} return result; }';

  final lenses = fields.map((f) {
    final name = f.name;
    final type = f.type;
    return 'static final $name = Lens<$className, $type>((s_) => s_.$name, (s_, $name) => s_.copyWith($name: $name));';
  });

  final constructor = 'const \$$className();';

  final dataClass =
      'abstract class \$$className { $constructor ${fieldDeclarations.join()} $copyWith $toString $equality $hash }';
  final lensesClass = 'class $className\$ { ${lenses.join()} }';

  final warningSuppressions = '''
// ignore_for_file: join_return_with_assignment
// ignore_for_file: avoid_classes_with_only_static_members
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes
''';

  return '$warningSuppressions $dataClass $lensesClass';
}

String _typeAsCode(DartType type) {
  if (type is FunctionType) {
    final positionArgs = type.parameters.where((p) => p.isPositional).map((p) => _typeAsCode(p.type)).join(', ');
    final namedArgs = type.parameters.where((p) => p.isNamed).map((p) => '${_typeAsCode(p.type)} ${p.name}').join(', ');

    final parameters = namedArgs.isEmpty ? positionArgs : positionArgs + ', {$namedArgs}';

    return '${_typeAsCode(type.returnType)} Function($parameters)';
  } else {
    return type.getDisplayString(withNullability: true);
  }
}

String _generateEquality(Field f) {
  if (f.customEquality != null) {
    return '${f.customEquality}.equals(${f.name}, other.${f.name})';
  } else {
    return '${f.name} == other.${f.name}';
  }
}

String _generateHash(Field f) {
  if (f.customEquality != null) {
    return '${f.customEquality}.hash(${f.name})';
  } else {
    return '${f.name}.hashCode';
  }
}

class Field {
  final String name;
  final String prefix;

  String get type => prefix == null ? _type : "$prefix.$_type";

  String get optionalType => type[type.length - 1] == '?' ? type : "$type?";
  final String customEquality;

  const Field(this.name, this.prefix, String type, this.customEquality) : _type = type;

  final String _type;
}
