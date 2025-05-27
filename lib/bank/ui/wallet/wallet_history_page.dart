import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:neom_commons/core/ui/widgets/appbar_child.dart';
import 'package:neom_commons/core/utils/app_color.dart';
import 'package:neom_commons/core/utils/app_theme.dart';
import 'package:neom_commons/core/utils/constants/app_page_id_constants.dart';
import 'package:neom_commons/core/utils/constants/app_translation_constants.dart';

import '../../../commerce/domain/models/app_transaction.dart';
import '../../../commerce/ui/widgets/transaction_tile.dart';
import '../../../commerce/ui/widgets/wallet_widgets.dart';
import 'wallet_card.dart';
import 'wallet_controller.dart';

class WalletHistoryPage extends StatelessWidget {
  const WalletHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<WalletController>(
      id: AppPageIdConstants.walletHistory,
      init: WalletController(),
      builder: (_) => Scaffold(
        appBar:  PreferredSize(
            preferredSize: const Size.fromHeight(50),
            child: AppBarChild(title: AppTranslationConstants.wallet.tr)
        ),
        backgroundColor: AppColor.main50,
        body: Container(
          decoration: AppTheme.appBoxDecoration,
          height: AppTheme.fullHeight(context),
          child: _.isLoading.value ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTheme.heightSpace20,
                Padding(padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: WalletCard(),
                ),
                AppTheme.heightSpace20,
                Divider(thickness: 1, color: AppColor.white80),
                SizedBox(
                  width: AppTheme.fullWidth(context),
                  child: Text(
                    AppTranslationConstants.transactionsHistory.tr,
                    style: const TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
                Divider(thickness: 1, color: AppColor.white80),
                SizedBox(
                  height: AppTheme.fullHeight(context)*0.7,
                  child: _.transactions.isNotEmpty ? ListView.builder(
                      itemCount: _.transactions.length,
                      itemBuilder: (context, index) {
                        AppTransaction transaction = _.transactions.values.elementAt(index);
                        return TransactionTile(transaction: transaction, walletId: _.wallet?.id ?? '',);
                      }
                  ) :  buildNoHistoryToShow(context, _),
                ),
                // SizedBox(
                //   height: AppTheme.fullHeight(context)*0.7,
                //   child: _.orders.isNotEmpty ? ListView.builder(
                //       itemCount: _.orders.length,
                //       itemBuilder: (context, index) {
                //         AppOrder order = _.orders.values.elementAt(index);
                //         return OrderTile(order: order);
                //       }
                //   ) :  buildNoHistoryToShow(context, _),
                // ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}
