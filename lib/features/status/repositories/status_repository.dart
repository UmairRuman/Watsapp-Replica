// ignore_for_file: public_member_api_docs, sort_constructors_first, use_build_context_synchronously
import 'dart:developer';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gossip_go/models/status_model.dart';
import 'package:gossip_go/repositories/firebase_storage_repo.dart';
import 'package:gossip_go/services/database_service.dart';
import 'package:gossip_go/utils/common_functions.dart';
import 'package:uuid/uuid.dart';

final statusRepositoryProvider = Provider<StatusRepository>((ref) {
  return StatusRepository(
      fireStore: FirebaseFirestore.instance,
      auth: FirebaseAuth.instance,
      ref: ref);
});

class StatusRepository {
  static const _statusCollection = 'status';
  final FirebaseFirestore fireStore;
  final FirebaseAuth auth;
  final ProviderRef ref;
  StatusRepository({
    required this.fireStore,
    required this.auth,
    required this.ref,
  });

  void uploadStatus({
    required BuildContext context,
    required String username,
    required String profilePicture,
    required String phoneNumber,
    required File statusImage,
  }) async {
    try {
      /**
       * the status should be visible to our contacts and if we a re added in theri contacts, we need the contacts of the user , we need to get all the users from firestore with that phone number(status uploader) in the users chat list, add the, in a list so it can be added to a status model, them we will chech if there is a status already present we will add the new status(image) to that list other wise we will add o status(image) 
       */

      var statusId = const Uuid().v1();
      var currentUser = FirebaseAuth.instance.currentUser!;
      var db = DBHelper();
      //we are going to store the status in the status folder and with the status and usr id
      var imageUrl =
          await ref.read(firebaseStorageRepositoryProvider).saveFileToStorage(
                path: '/status/$statusId${currentUser.uid}',
                file: statusImage,
              );
      List<String> visibleToUids = [];

      var appUsers = await db.getAppUsers();

      for (var i = 0; i < appUsers.length; i++) {
        visibleToUids.add(appUsers[i].uid);
      }

      List<String> statusImageUrls = [];
      //if a status already exists then we will add the status ,
      var userStatuses = await fireStore
          .collection(_statusCollection)
          .where(
            'uid',
            isEqualTo: currentUser.uid,
          )
          // we can also get the last 24 hr statuses like this
          // .where(
          //   'created',
          //   isLessThan: DateTime.now().add(
          //     const Duration(
          //       hours: 24,
          //     ),
          //   ),
          // )
          .get();

      if (userStatuses.docs.isNotEmpty) {
        //we are getting the already existing status and then adding the new status to the list of statuses, and the status will be at the first index of the docs,os we donot iterate the whole list
        var status = StatusModel.fromMap(userStatuses.docs[0].data());
        statusImageUrls = status.photosUrl;
        statusImageUrls.add(imageUrl);
        //now that we have added the new status, we need to update it on the firestore also, so first we will get the doc where the list is stored and then update the list of statuses
        fireStore
            .collection(_statusCollection)
            .doc(userStatuses.docs[0].id)
            .update({
          'photosUrl': statusImageUrls,
        });
        log('status uplaoded');
        return;
      } else {
        statusImageUrls = [imageUrl];
      }

      var newStatus = StatusModel(
          uid: currentUser.uid,
          userName: username,
          phoneNumber: phoneNumber,
          photosUrl: statusImageUrls,
          createdTime: DateTime.now(),
          profilePic: profilePicture,
          statusId: statusId,
          visibleTo: visibleToUids);
      await fireStore
          .collection(_statusCollection)
          .doc(statusId)
          .set(newStatus.toMap());
      log('status uploaded');
    } catch (e) {
      showSnackBar(context: context, data: e.toString());
      log(e.toString());
    }
  }

  // this function will get all the statuses to Show
  Future<List<StatusModel>> getStatuses({
    required BuildContext context,
  }) async {
    List<StatusModel> statuses = [];
    try {
      var db = DBHelper();
      var appUsers = await db.getAppUsers();
      for (var i = 0; i < appUsers.length; i++) {
        var userStatuses = await fireStore
            .collection(_statusCollection)
            .where(
              'phoneNumber',
              isEqualTo: appUsers[i].phoneNumber,
            )
            .where(
              'createdTime',
              isGreaterThan: DateTime.now()
                  .subtract(
                    const Duration(
                      hours: 24,
                    ),
                  )
                  .millisecondsSinceEpoch,
            )
            .get();

        for (var statusDoc in userStatuses.docs) {
          //we will iterate through whole docs and get the statuses of all the other users
          var otherUser = StatusModel.fromMap(statusDoc.data());
          //now we will check that if the other user has added the current user in their contact list only then we will show their status to the current user
          if (otherUser.visibleTo.contains(auth.currentUser!.uid)) {
            bool isAlreadyPresent = false;
            for (var element in statuses) {
              if (element.phoneNumber == otherUser.phoneNumber) {
                isAlreadyPresent = true;
              }
            }
            if (!isAlreadyPresent) {
              statuses.add(otherUser);
            }
          }
        }
      }
      log('statuses fetched'); 
    } catch (e) {
      log('status Error : ${e.toString()}');
      showSnackBar(context: context, data: e.toString());
    }
    return statuses;
  }

  Future<StatusModel?> getUserStatus() async {
    var firesStoreStatus = await fireStore
        .collection(_statusCollection)
        .where('phoneNumber',
            isEqualTo: FirebaseAuth.instance.currentUser!.phoneNumber)
        .where('createdTime',
            isGreaterThan: DateTime.now()
                .subtract(
                  const Duration(
                    hours: 24,
                  ),
                )
                .millisecondsSinceEpoch)
        .get();
    StatusModel? status;
    for (var userStatus in firesStoreStatus.docs) {
      status = StatusModel.fromMap(userStatus.data());
    }
    return status;
  }
}
