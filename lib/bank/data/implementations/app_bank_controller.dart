import 'dart:async';

import 'package:get/get.dart';

import 'package:neom_commons/core/utils/app_utilities.dart';
import 'package:neom_commons/core/utils/constants/message_translation_constants.dart';

import '../../../commerce/domain/models/app_transaction.dart';
import '../../../commerce/domain/models/wallet.dart';
import '../../../commerce/utils/enums/payment_status.dart';
import '../../../commerce/utils/enums/transaction_type.dart';
import '../../utils/bank_constants.dart';
import '../transaction_firestore.dart';
import '../wallet_firestore.dart';

class AppBankController {

  static final AppBankController _instance = AppBankController._internal();

  factory AppBankController() {
    _instance._init();
    return _instance;
  }

  AppBankController._internal();
  bool _isInitialized = false;

  TransactionStatus transactiontStatus = TransactionStatus.pending;
  Wallet wallet = Wallet();

  /// Inicialización manual para controlar mejor el ciclo de vida
  Future<void> _init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    AppUtilities.logger.t('AppBankController Controller Initialization');

    try {

    } catch (e) {
      AppUtilities.logger.e(e.toString());
    }
  }

  Future<bool> processTransaction(AppTransaction transaction) async {
    AppUtilities.logger.d('Processing transaction: ${transaction.id}');

    try {
      if(BankConstants.userTransactions.contains(transaction.type)
          && (wallet.balance < transaction.amount)) {
        AppUtilities.logger.e(MessageTranslationConstants.notEnoughFundsMsg.tr);
        return false;
      }

      if(await WalletFirestore().addTransaction(transaction)) {
        AppUtilities.logger.d('Transaction added successfully: ${transaction.id}');
        transaction.status = TransactionStatus.completed;
      } else {
        AppUtilities.logger.d('Failed to add transaction: ${transaction.id}');
        transaction.status = TransactionStatus.failed;
      }

      TransactionFirestore().updateStatus(transaction.id, transaction.status);
    } catch (e) {
      AppUtilities.logger.e(e.toString());
      return false;
    }


    return transaction.status == TransactionStatus.completed;
  }

  Future<bool> addCoinsToWallet(String walletId, double amount, {TransactionType transactionType = TransactionType.purchase}) async {
    AppUtilities.logger.d('Adding $amount coins to wallet: $walletId');

    AppTransaction transaction = AppTransaction(
      amount: amount,
      recipientId: walletId,
      type: transactionType,
    );

    try {
      transaction.id = await TransactionFirestore().insert(transaction);
      if(transaction.amount > 0) {
        if(await WalletFirestore().addTransaction(transaction)) {
          AppUtilities.logger.d('Coins added to wallet: $walletId');
          transaction.status = TransactionStatus.completed;
        } else {
          AppUtilities.logger.e('Failed to add coins to wallet: $walletId');
          transaction.status = TransactionStatus.failed;
        }
        TransactionFirestore().updateStatus(transaction.id, transaction.status);
      } else {
        return false;
      }
    } catch (e) {
      AppUtilities.logger.e(e.toString());
      return false;
    }

    return transaction.status == TransactionStatus.completed;
  }

}
