import haxe.Serializer;
import haxe.Unserializer;
import hext.HExt;

#if js
import js.Browser.document;
import js.html.Element;
#end

class Main {

	static function main() {

		// Some data
		var people = [
			{fname:"Jill", lname:"Smith", age:50},
			{fname:"Eve", lname:"Jackson", age:94}
		];

#if hextclone
		buildByParser(people);
#end

#if hextclonejs
		buildByDOM(people);
#end

	}

#if hextclone
	static function buildByParser(people:Array<{fname:String,lname:String,age:Int}>) {
		// This example will use the htmlparser library to build a table in-memory based on the parsed template data

		// Create an instance of the table template
		var userTable1 = HTMLTemplates.usertable.table.clone();

		// Add rows to the instance
		var rows:Array<hext.usertable.table.tbody.row.Row_Clone> = [];
		for(p in people) {
			var row = HTMLTemplates.usertable.table.tbody.row.clone();
			row.firstname.innerHTML = p.fname;
			row.lastname.innerHTML = p.lname;
			row.age.innerHTML = Std.string(p.age);
			userTable1.tbody.addChild(row);
			rows.push(row);
		}

		#if php
		// Server side templating, simply dump the htmlparser string out
		Sys.print(userTable1.toString());
		#end

		#if js
		// Client side templating can be more dynamic

		// If direct to DOM and we don't need access to the elements, use HExt.toElement()
		document.body.appendChild(HExt.toElement(userTable1));

		// Once DOM elements are created the HtmlParser objects and DOM can become out of sync, get the generated 'named' template elements using HExt.toElementMap()
		var emap = HExt.toElementMap(userTable1);
		document.body.appendChild(emap.root);

		// For example, update data on the original cloned template instance - the data is 'detached' from the real DOM!
		rows[0].firstname.innerHTML = "SOMEBODY ELSE";
		// By using toElementMap during generation the hext names can be used to track down the actual instances
		emap.map["firstname"][1].innerHTML = rows[0].firstname.innerHTML;

		// Another 'empty' instance
		document.body.appendChild(HExt.toElement(HTMLTemplates.usertable.table.clone()));
		#end
	}
#end

#if hextclonejs
	static function buildByDOM(people:Array<{fname:String,lname:String,age:Int}>) {
		// This example will use the compile-time macro to build a table directly into DOM elements
		// Changes to the template are NOT reflected in the cloneDOM output!

		// Create an instance of the table template
		var userTable1 = HTMLTemplates.usertable.table.cloneDOM();
		document.body.appendChild(userTable1._); // Add to DOM - we have direct pointers to all hext named elements, so future DOM edits are easy

		// Add rows to the instance
		for(p in people) {
			var row = HTMLTemplates.usertable.table.tbody.row.cloneDOM();
			row.firstname._.innerHTML = p.fname;
			row.lastname._.innerHTML = p.lname;
			row.age._.innerHTML = Std.string(p.age);
			userTable1.tbody._.appendChild(row._);
		}
	}
#end
}
