class Student {
  int? id;
  String name;
  String rollNum;
  String fatherName;
  String contact;
  String studentClass;
  String gender;
  String discipline;
  double totalPackage;
  double paperFund;
  String? firebaseId;

  Student({
    this.id,
    required this.name,
    required this.rollNum,
    required this.fatherName,
    required this.contact,
    required this.studentClass,
    required this.gender,
    required this.discipline,
    required this.totalPackage,
    this.paperFund = 1000,
    this.firebaseId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'rollNum': rollNum,
      'fatherName': fatherName,
      'contact': contact,
      'class': studentClass,
      'gender': gender,
      'discipline': discipline,
      'totalPackage': totalPackage,
      'paperFund': paperFund,
      'firebaseId': firebaseId,
    };
  }

  factory Student.fromMap(Map<String, dynamic> map) {
    return Student(
      id: map['id'],
      name: map['name'],
      rollNum: map['rollNum'],
      fatherName: map['fatherName'],
      contact: map['contact'],
      studentClass: map['class'],
      gender: map['gender'],
      discipline: map['discipline'],
      totalPackage: map['totalPackage'],
      paperFund: map['paperFund'] ?? 1000,
      firebaseId: map['firebaseId'],
    );
  }
}

