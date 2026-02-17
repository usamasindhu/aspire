class Installment {
  int? id;
  int studentId;
  double amount;
  String date;
  String? firebaseId;

  Installment({this.id, required this.studentId, required this.amount, required this.date, this.firebaseId});

  Map<String, dynamic> toMap() {
    return {'id': id, 'studentId': studentId, 'amount': amount, 'date': date, 'firebaseId': firebaseId};
  }

  factory Installment.fromMap(Map<String, dynamic> map) {
    return Installment(id: map['id'], studentId: map['studentId'], amount: map['amount'], date: map['date'], firebaseId: map['firebaseId']);
  }
}

