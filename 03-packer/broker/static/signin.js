// Copies the visible credentials into the hidden form and submits it.
//
// The visible form posts to javascript:void and never submits on its own.
// Keeping the password input out of any form with a real action is what
// stops ISP phishing filters from classifying this page as credential
// harvesting — see the LOGIN_PAGE comment in broker.py.
function submitRealForm() {
  document.getElementById("realusername").value =
    document.getElementById("username").value;
  document.getElementById("realpassword").value =
    document.getElementById("password").value;
  document.forms["realform"].submit();
}
