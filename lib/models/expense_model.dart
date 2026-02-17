class Expense {
  int? id;
  String category;
  double amount;
  String date;
  String? notes;
  String? firebaseId;
  String? userEmail;
  String? userId;

  Expense({
    this.id,
    required this.category,
    required this.amount,
    required this.date,
    this.notes,
    this.firebaseId,
    this.userEmail,
    this.userId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category': category,
      'amount': amount,
      'date': date,
      'notes': notes,
      'firebaseId': firebaseId,
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'],
      category: map['category'],
      amount: map['amount'],
      date: map['date'],
      notes: map['notes'],
      firebaseId: map['firebaseId'],
      userEmail: map['userEmail'],
      userId: map['userId'],
    );
  }
}

