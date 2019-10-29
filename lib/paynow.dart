library paynow;


import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class HashMismatchException implements Exception{
  String cause;
  HashMismatchException(this.cause);
}

class ValueError implements Exception{
  String cause;
  ValueError(this.cause);
}

class StatusResponse{

  String paid;

  String status;

  var amount;

  String reference;

  String hash;

  StatusResponse({this.paid, this.status,this.amount,this.reference, this.hash});

  static fromJson(Map<String, dynamic> data){

    return StatusResponse(
      paid: data['paid'],
      status: data['status'],
      amount: data['amount'],
      reference: data['reference'],
      hash: data['hash']
    );
  }
}


class InitResponse{
  bool success;

  String instructions;

  bool hasRedirect;

  String hash;

  String redirectUrl;

  String error;

  String pollUrl;

  InitResponse({this.redirectUrl, this.hasRedirect, this.pollUrl, this.error, this.success, this.hash, this.instructions});

  call(){
    Map<String, dynamic> data = {"redirect" : this.redirectUrl, "hasRedirect" : this.hasRedirect,"pollUrl" : this.pollUrl,"error" : this.error,"success" : this.success,"hash" : this.hash, "instructions" : this.instructions};
    // TODO:/// Refactor
    return data;
  }


  static fromJson(Map<String, dynamic> data){
    return InitResponse(
      success: data['status']!="error",
      error: data['error'].toString().toLowerCase(),
      hash: data['hash'],
      hasRedirect: data['browserurl'] != null,
      redirectUrl: data['browserurl'],
      instructions: data['instructions'],
      pollUrl: data['pollurl']
    );
  }
}


class Payment{
  String reference;

  List<Map<String, dynamic>> items=[];

  String authEmail;

  Payment({String reference, String authEmail}){
    this.authEmail=authEmail;
    this.reference = reference;
  }

  Payment add(String title, double amount){

    this.items.add({"title" : title, "amount" : amount});

    return this;
  }

  String info(){
    String out = "";
    for (int i=0; i<this.items.length;i++){
      out+=this.items.elementAt(i)["title"];
    }
    out+="%2C+";

    return out;
  }

  double total(){
    double total=0.0;

    if (this.items.length==0) return 0.0;

    for (int i=0;i<this.items.length;i++){
      total+=this.items[i]['amount'];
    }
    return total;
  }
}


class Paynow{
  static const String URL_INITIATE_TRANSACTION = "https://www.paynow.co.zw/interface/initiatetransaction";
  static const String URL_INITIATE_MOBILE_TRANSACTION = "https://www.paynow.co.zw/interface/remotetransaction";

  String integrationId;

  String integrationKey;

  String returnUrl;

  Function onError;

  Function onCheck;

  Function onDone;

  String resultUrl;

  Paynow({this.integrationId, this.integrationKey, this.returnUrl, this.resultUrl});

  Payment createPayment(String reference, String authEmail){

    return Payment(reference: reference, authEmail: authEmail);
  }



  Future<InitResponse> _init(Payment payment)async{

    if (payment.total() < 0 || payment.total() == 0){
      throw ValueError("Transaction Total Invalid");
    }

    Map<String, dynamic> data = _build(payment);
    var client=http.Client();
    var response = await client.post(Paynow.URL_INITIATE_TRANSACTION, body: data);

    return InitResponse.fromJson(this._rebuildResponse(response.body));


  }

  String _quotePlus(String value){

    try{
      return value.replaceAll(":", "%3A").replaceAll("/", "%2F");
    }catch(e){
      this.onError(e);
      return "";
    }
  }

  static String notQuotePlus(String value){
    // lazy way
    return value.replaceAll("%3A", ":").replaceAll("%2F", "/").replaceAll("%3a", ":").replaceAll("%2f", "/").replaceAll("%3f", "?").replaceAll("%3d", "=");

  }

  Map<String, dynamic> _rebuildResponse(String qry){

  	List<String> q = qry.split("&");
  	Map<String, dynamic> data={};
  	for(int i=0;i<q.length;i++){
  		List<String> parts = q[i].split("=");
  		data[parts[0]] = parts[1];
  	}
  	return data;
  }


  Map<String, dynamic> _build(Payment payment){

    Map<String, dynamic> body = {
      "resulturl" : this.resultUrl,
      "returnurl" : this.returnUrl,
      "reference" : payment.reference,
      "amount" : payment.total(),
      "id" : this.integrationId,
      "additionalinfo" : payment.info(),
      "authemail" : payment.authEmail ?? "",
      "status" : "Message"
    };

    body.keys.forEach((f){

        String _p = _quotePlus(body[f].toString());
        body[f] = _p;
    });



    String out = _stringify(body);

    body['hash'] = _generateHash(out);

    return body;
  }


  Future<StatusResponse> checkTransactionStatus(String pollUrl)async{


    var response = await http.post(pollUrl.replaceAll("%3a", ":").replaceAll("%2f", "/").replaceAll("%3d", "=").replaceAll("%3f", "?"));
    return StatusResponse.fromJson(this._rebuildResponse(response.body));

  }

  Future<InitResponse> _initMobile(Payment payment, String phone, String method)async{


      if (payment.total()==0) throw Exception("Invalid Total");
      Map<String, dynamic> data = await _buildMobile(payment, phone, method);
      var client=http.Client();
      var response = await client.post(Paynow.URL_INITIATE_MOBILE_TRANSACTION, body: data);
      return InitResponse.fromJson(this._rebuildResponse(response.body));

  }

  _buildMobile(Payment payment, String phone, String method)async{

    Map<String, dynamic> body = {
      "resulturl" : this.resultUrl,
      "returnurl" : this.returnUrl,
      "reference" : "asf",
      "amount" : payment.total(),
      "id" : this.integrationId,
      "additionalinfo" : payment.info(),
      "authemail" : "g@gmail.com",
      "status" : "Message",
      "phone" : phone,
      "method" : method
    };


    body.keys.forEach((f){
      if(f=="authemail"){
        // skip auth
      }else{
        body[f] = _quotePlus(body[f].toString());
      }
    });

    String out = _stringify(body);

    body["hash"] = _generateHash(out); //await __hash(body);

    return body;
  }

  String _stringify(Map<String, dynamic> body){
    String out = "";

    List<String> values = body.keys.toList();
    for (int i=0;i<values.length;i++){
      if (values[i]=="hash"){
        continue;
      }


      out += body[values[i]];

    }

    out+=this.integrationKey;


    return out;
  }

  String _generateHash(String string){
    return sha512.convert(utf8.encode(string)).toString().toUpperCase();
  }

  Future<InitResponse> sendMobile(Payment payment, String phone, String method){
    return this._initMobile(payment, phone, method);
  }

  Future<InitResponse> send(Payment payment){
    return this._init(payment);
  }

}


main(){
  Paynow paynow = Paynow(integrationKey: "960ad10a-fc0c-403b-af14-e9520a50fbf4", integrationId: "6054", returnUrl: "http://google.com", resultUrl: "http://google.co");
  Payment payment = paynow.createPayment("user", "user@email.com");

  payment.add("Banana", 1.9);


  // Initiate Paynow Transaction
  paynow.send(payment)
  ..then((InitResponse response){

    // display results
    print(response());

    // Check Transaction status from pollUrl
    String url = Paynow.notQuotePlus(response.pollUrl);
    print(Paynow.notQuotePlus(response.pollUrl));
    paynow.checkTransactionStatus(url)
    ..then((StatusResponse status){
      print(status.paid);
      print(status.reference);
      print(status.status);
    });
  });


  // paynow.sendMobile(payment, "0784442662", "ecocash")
  //   ..then((InitResponse response){
  //     // display results
  //     print(response());
  //
  //     // Check Transaction status from pollUrl
  //     paynow.checkTransactionStatus(response.pollUrl)
  //       ..then((StatusResponse status){
  //         print(status.paid);
  //       });
  //   });

}
