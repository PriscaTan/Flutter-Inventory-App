import 'package:bk_app/models/user.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:bk_app/models/item.dart';

class FormUtils {
  static String fmtToIntIfPossible(double value) {
    if (value == null) {
      return '';
    }

    String intString = '${value.ceil()}';
    if (double.parse(intString) == value) {
      return intString;
    } else {
      return '$value';
    }
  }

  static double getShortDouble(double value, {round = 2}) {
    return double.parse(value.toStringAsFixed(round));
  }

  static bool isDatabaseOwner(UserData userData) {
    return userData.targetEmail == userData.email;
  }

  static bool isTransactionOwner(UserData userData, transaction) {
    return transaction.signature == userData.email;
  }

  static Future<bool> saveTransactionAndUpdateItem(
      transaction, item, String itemId,
      {String transactionId, userData}) async {
    Firestore db = Firestore.instance;
    bool success = true;

    String targetEmail = userData.targetEmail;
    WriteBatch batch = db.batch();

    try {
      if (transactionId == null) {
        // Insert operation
        transaction.createdAt = DateTime.now().millisecondsSinceEpoch;
        transaction.date = DateFormat.yMMMd().add_jms().format(DateTime.now());
        if (transaction.type == 1) item.lastStockEntry = transaction.date;
        transaction.signature = userData.email;
        batch.setData(db.collection('$targetEmail-transactions').document(),
            transaction.toMap());
      } else {
        // Update operation
        if (!isDatabaseOwner(userData) &&
            !isTransactionOwner(userData, transaction)) {
          return false;
        } else {
          transaction.signature = userData.email;
          batch.updateData(
              db
                  .collection('$targetEmail-transactions')
                  .document(transactionId),
              transaction.toMap());
        }
      }

      item.used += 1;

      if (isDatabaseOwner(userData)) {
        // Item should only be modified by the owner of database. When some one other that owner creates or
        // updates the transactins items is not changed and only transaction change with the sign of them
        // Later when owner accepts it (by just resaving) this condition is passed and item is changed
        print("db owner so updating item $item");
        batch.updateData(
            db.collection('$targetEmail-items').document(itemId), item.toMap());
      }

      batch.commit();
    } catch (e) {
      success = false;
    }
    return success;
  }

  static void deleteTransactionAndUpdateItem(callback, transaction,
      transactionId, DocumentSnapshot itemSnapshot, userData) async {
    // Sync newly updated item and delete transaction from db in batch
    Firestore db = Firestore.instance;
    bool success = true;
    String targetEmail = userData.targetEmail;
    WriteBatch batch = db.batch();

    if (!isDatabaseOwner(userData) &&
        !isTransactionOwner(userData, transaction)) {
      callback(false);
      return;
    }

    if (itemSnapshot?.data == null || !isDatabaseOwner(userData)) {
      //Condition 1:
      // Those transaction whose relating item are deleted are orphan transactions
      // The item associated can't be modified so we can just delete transaction only

      //Condition 2:
      // The case is similar for transactions not created by owner they are classified as
      // draft and item associated to them should not change until owner verfies/owns it.

      batch.delete(
          db.collection('$targetEmail-transactions').document(transactionId));
      batch.commit();
      callback(success);
      return;
    }

    // Reset item to state before this sales transaction
    Item item = Item.fromMapObject(itemSnapshot.data);
    item.used += 1;

    if (transaction.type == 0) {
      item.increaseStock(transaction.items);
    } else {
      item.decreaseStock(transaction.items);
    }
    try {
      batch.delete(
          db.collection('$targetEmail-transactions').document(transactionId));
      batch.updateData(
          db.collection('$targetEmail-items').document(itemSnapshot.documentID),
          item.toMap());
      batch.commit();
    } catch (e) {
      success = false;
    }

    callback(success);
  }
}
