import 'dart:typed_data';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:hive_generator/src/builder.dart';
import 'package:source_gen/source_gen.dart';

class ClassBuilder extends Builder {
  var listChecker = const TypeChecker.fromRuntime(List);
  var mapChecker = const TypeChecker.fromRuntime(Map);
  var setChecker = const TypeChecker.fromRuntime(Set);
  var iterableChecker = const TypeChecker.fromRuntime(Iterable);
  var uint8ListChecker = const TypeChecker.fromRuntime(Uint8List);

  ClassBuilder(ClassElement cls, Map<int, FieldElement> fields)
      : super(cls, fields);

  @override
  String buildRead() {
    var code = StringBuffer();
    code.writeln('''
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ${cls.name}(
    ''');

    var constructor = cls.constructors.firstWhere(
      (constructor) => constructor.name.isEmpty,
      orElse: () => throw AssertionError('Provide an unnamed constructor.'),
    );

    // The remaining fields to initialize.
    var remainingFields = <String, int>{
      for (var entry in fields.entries) entry.value.name: entry.key,
    };

    for (var param in constructor.parameters
        .where((param) => param.isInitializingFormal)) {
      var index = remainingFields.remove(param.name);
      if (index == null) {
        // This is a parameter of the form `this.field`, but it's not present
        // in the binary encoding.
        continue;
      }

      if (param.isNamed) {
        code.write('${param.name}: ');
      }
      code.writeln('${_cast(param.type, 'fields[$index]')},');
    }

    code.writeln(')');

    // There may still be fields to initialize that were not in the constructor
    // as initializing formals. We do so using cascades.
    for (var entry in remainingFields.entries) {
      var field = entry.key;
      var index = entry.value;
      var type = fields[index].type;
      code.writeln('..$field = ${_cast(type, 'fields[$index]')}');
    }

    code.writeln(';');

    return code.toString();
  }

  String _cast(DartType type, String variable) {
    if (iterableChecker.isAssignableFromType(type) && !isUint8List(type)) {
      return '($variable as List)${_castIterable(type)}';
    } else if (mapChecker.isExactlyType(type)) {
      return '($variable as Map)${_castMap(type)}';
    } else {
      return '$variable as ${type.name}';
    }
  }

  bool isMapOrIterable(DartType type) {
    return listChecker.isExactlyType(type) ||
        setChecker.isExactlyType(type) ||
        iterableChecker.isExactlyType(type) ||
        mapChecker.isExactlyType(type);
  }

  bool isUint8List(DartType type) {
    return uint8ListChecker.isExactlyType(type);
  }

  String _castIterable(DartType type) {
    var paramType = type as ParameterizedType;
    var arg = paramType.typeArguments[0];
    if (isMapOrIterable(arg) && !isUint8List(arg)) {
      var cast = '';
      if (listChecker.isExactlyType(type)) {
        cast = '?.toList()';
      } else if (setChecker.isExactlyType(type)) {
        cast = '?.toSet()';
      }
      return '?.map((dynamic e)=> ${_cast(arg, 'e')})$cast';
    } else {
      return '?.cast<${arg.name}>()';
    }
  }

  String _castMap(DartType type) {
    var paramType = type as ParameterizedType;
    var arg1 = paramType.typeArguments[0];
    var arg2 = paramType.typeArguments[1];
    if (isMapOrIterable(arg1) || isMapOrIterable(arg2)) {
      return '?.map((dynamic k, dynamic v)=>'
          'MapEntry(${_cast(arg1, 'k')},${_cast(arg2, 'v')}))';
    } else {
      return '?.cast<${arg1.name}, ${arg2.name}>()';
    }
  }

  @override
  String buildWrite() {
    var code = StringBuffer();
    code.writeln('writer');
    code.writeln('..writeByte(${fields.length})');
    fields.forEach((index, field) {
      var value = _convertIterable(field.type, 'obj.${field.name}');
      code.writeln('''
      ..writeByte($index)
      ..write($value)''');
    });
    code.writeln(';');

    return code.toString();
  }

  String _convertIterable(DartType type, String accessor) {
    if (setChecker.isExactlyType(type) || iterableChecker.isExactlyType(type)) {
      return '$accessor?.toList()';
    } else {
      return accessor;
    }
  }
}
