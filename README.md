# HExt

This Haxe tool is for quickly converting html into code that can be output on the server or client side.  

For example, an html mockup is created of the page and you want to incorporate it into a project and apply some data.  

Add the html to the 'htmltemplates' folder and use the `hext` attributes to tell the system which pieces you want direct access to. 
The macro that runs on the `HTMLTemplates` class will convert the html into cloneable template nodes for use with the HTMLParser library (`-D hextclone` build define), or directly into Javascript DOM createElement calls (`-D hextclonejs` build define).  

The HTML file 'usertable.htm':
```html
<table style="width:100%" hext="table">
    <thead>
    <tr>
      <th>Firstname</th>
      <th>Lastname</th>
      <th>Age</th>
    </tr>
  </thead>
  <tbody hext="tbody">
    <tr hext="row" hext-remove>
      <td hext="firstname"></td>
      <td hext="lastname"></td>
      <td hext="age"></td>
    </tr>
  </tbody>
  </table>
  ```
 When parsed provides code-completion:
  ```haxe
  // Using -D hextclone
  var userTable = HTMLTemplates.usertable.table.clone(); // Create an instance of htmlparser.HtmlNodeElement
  // Using -D hextclonejs
  var userTable = HTMLTemplates.usertable.table.cloneDOM(); // Create a DOM instance with {_:Element, tbody:{_:Element, ..children }}
  ```