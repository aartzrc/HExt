package hext;

#if macro
import haxe.io.Path;
import sys.io.File;
import sys.FileSystem;
import haxe.macro.Context;
import haxe.macro.Expr;
import hext.HExt;
import haxe.Serializer;

import htmlparser.HtmlParser;
import htmlparser.HtmlNodeElement;
import htmlparser.HtmlNodeText;

using StringTools;
using Lambda;

class HExtBuilder {

	public static function addHTML(htmlPath:String):Array<Field> {
		// get existing fields from the context from where build() is called
        var fields = Context.getBuildFields();
		for(curFileName in FileSystem.readDirectory(htmlPath)) {
            //trace("Parsing template: " + Path.join([htmlPath, curFileName]));
            var path = Path.join([htmlPath, curFileName]);
			var htmlStr = File.getContent(path);

			var fieldName = curFileName;
            if(fieldName.indexOf(".") != -1) fieldName = fieldName.substring(0, fieldName.indexOf("."));
            fieldName = cleanFieldName(fieldName);

            // Recurse fields
            var elements = processChunk_HtmlParser({path:path, chunk:htmlStr});
            if(elements.length > 0) { // HExt elements found
                // Create a dummy root node that matches the html file name
                var node:HtmlNodeElementExt = {
                    name:fieldName,
                    children:elements,
                    node:null,
                    cloneChildren:elements,
                    pos:{min:0, max:htmlStr.length, file:Path.join([htmlPath, curFileName])}
                };
                // defineAbstract will recursively create 'wrappers' around the HtmlNodeElement data
                var rootAbstract = defineAbstract(node, ["hext"]);
                var rootField:Field = {
                    name: fieldName,
                    access: [Access.APublic, Access.AStatic],
                    kind: FVar(TPath({pack:rootAbstract.pack, name:rootAbstract.name}), null), 
                    pos: Context.makePosition(node.pos),
                };
                fields.push(rootField);
            }
		}
				
		return fields;
    }
    
    static function defineAbstract(childNode:HtmlNodeElementExt, curPack:Array<String>) {
        curPack = curPack.concat([cleanFieldName(childNode.name)]);
        var newAbstract:TypeDefinition = {
            pos:Context.makePosition(childNode.pos),
            pack:curPack,
            name: cleanTypeName(childNode.name),
            kind: TDAbstract(macro:htmlparser.HtmlNodeElement, [macro:htmlparser.HtmlNodeElement], []),
            fields: [],
            meta: [{pos:Context.currentPos(), name:":forward"}]
        }

        //trace('Define: ${curPack.join(".")}');

        if(childNode.node != null) {
#if hextclone
            // Create 'clone' method and abstract
            var cloneAbstract = defineAbstract_Clone(childNode, curPack);
            var clone:Field = {
                pos:Context.makePosition(childNode.pos),
                name:"clone",
                kind: FFun({args:[], expr:macro {
                    haxe.Serializer.USE_CACHE = true;
		            return haxe.Unserializer.run(haxe.Serializer.run(this));
                },ret:TPath({pack:cloneAbstract.pack, name:cloneAbstract.name})}), 
                access: [APublic]
            }
            newAbstract.fields.push(clone);
#end

#if hextclonejs
            // Create 'cloneDOM' method
            var cloneDOM:Field = {
                pos:Context.makePosition(childNode.pos),
                name:"cloneDOM",
                kind: FFun({args:[{type:macro:js.html.Element,opt:true,name:"parent"}], expr:toDOMElements(childNode),ret:null}), 
                access: [APublic]
            }
            newAbstract.fields.push(cloneDOM);
#end
        }

        // Create handlers for the hext children
        for(child in childNode.children) {
            var childAbstract = defineAbstract(child, curPack);
            var childType = TPath({pack:childAbstract.pack, name:childAbstract.name});

#if hextclone
            // Static field that stores the 'template' node - this will be lazy created by the 'getter'
            var sVar:Field = {
                pos:Context.makePosition(childNode.pos),
                name:"_" + cleanFieldName(child.name),
                kind: FVar(childType, null), 
                access: [AStatic, APrivate]
            }
            newAbstract.fields.push(sVar);
            Serializer.USE_CACHE = true;
            var serializedNode = Serializer.run(child.node);
#end
            // Property to access the 'template'
            var prop:Field = {
                pos:Context.makePosition(childNode.pos),
                name:cleanFieldName(child.name),
                kind: FProp("get","never",childType), 
                access: [APublic]
            }
            
            // Property 'get' function which will lazy create the static instance from the serialized node
            var getFunc:Field = {
                pos:Context.makePosition(childNode.pos),
                name:"get_" + cleanFieldName(child.name),
                kind: FFun({args:[], expr:macro {
#if hextclone
                    if($i{sVar.name} == null) $i{sVar.name} = haxe.Unserializer.run($v{serializedNode});
                    return $i{sVar.name};
#else
                    return null;
#end
                },ret:childType}), 
                access: [APrivate]
            }
            newAbstract.fields.push(prop);
            newAbstract.fields.push(getFunc);
        }

        Context.defineType(newAbstract);

        return newAbstract;
    }

    static function defineAbstract_Clone(childNode:HtmlNodeElementExt, curPack:Array<String>) {
        var newAbstract:TypeDefinition = {
            pos:Context.makePosition(childNode.pos),
            pack:curPack,
            name: cleanTypeName(childNode.name) + "_Clone",
            kind: TDAbstract(macro:htmlparser.HtmlNodeElement, [macro:htmlparser.HtmlNodeElement], [macro:htmlparser.HtmlNodeElement]),
            fields: [],
            meta: [{pos:Context.currentPos(), name:":forward"}]
        }

        // Create handlers for the hext children 'clone's
        for(cloneChild in childNode.cloneChildren) {
            var cloneChildType = TPath({pack:curPack.concat([cloneChild.name]), name:cleanTypeName(cloneChild.name) + "_Clone"});
            // Property to access the cloned child
            var prop:Field = {
                pos:Context.makePosition(childNode.pos),
                name:cleanFieldName(cloneChild.name),
                kind: FProp("get","never",cloneChildType), 
                access: [APublic]
            }
            var getFunc:Field = {
                pos:Context.makePosition(childNode.pos),
                name:"get_" + cleanFieldName(cloneChild.name),
                kind: FFun({args:[], expr:macro {
                    return hext.HExt.findNode(this, $v{cloneChild.name});
                },ret:cloneChildType}), 
                access: [APrivate]
            }
            newAbstract.fields.push(prop);
            newAbstract.fields.push(getFunc);
        }

        Context.defineType(newAbstract);

        return newAbstract;
    }

    static function toDOMElements(node:HtmlNodeElementExt, ignoreAttrs:Array<String> = null):haxe.macro.Expr {
        if(ignoreAttrs == null) ignoreAttrs = [ HExt.attr, HExt.removeAttr, HExt.removeChildrenAttr ];
        var exprs:Array<Expr> = [];
        
        var elementCount = 0;
        function recurseChildren(nodeExt:HtmlNodeElementExt, node:HtmlNodeElement, parentVar:String = null, curProps:Array<ObjectField> = null) {
            // Create this element
            var tempName = 't$elementCount';
            elementCount++;
            var pos = Context.makePosition(nodeExt.pos);
            // Build Haxe js.html type to help with code completion
            var finalType = checkType(node.name);
            var createExpr:Expr = macro js.Browser.document.createElement($v{node.name});
            var assignExpr:Expr = {expr:ECast(createExpr, finalType), pos:pos};
            var castExpr:Expr = {expr:ECast(macro $i{tempName}, finalType), pos:pos};
            var varExpr:Expr = {
                pos:pos,
                expr: EVars([{
                    type:finalType,
                    name:tempName,
                    expr:assignExpr
                }])
            };
            exprs.push(macro var $tempName = js.Browser.document.createElement($v{node.name}));
            for(attr in node.attributes.filter((a) -> ignoreAttrs.indexOf(a.name) == -1)) {
                exprs.push(macro $i{tempName}.setAttribute($v{attr.name}, $v{attr.value}));
            }

            // curProps is null, this is the top-level node so always save it
            if(curProps == null) {
                curProps = [];
                curProps.push({field:"_",expr:castExpr});
            } else {
                // Check for a 'cloneChild' - this is a named child of the level above
                var cloneChild = nodeExt.cloneChildren.find((c) -> c.node == node);
                if(cloneChild != null) {
                    var newProps:Array<ObjectField> = [ {field:"_",expr:castExpr} ];
                    curProps.push({field:cleanFieldName(cloneChild.name),expr:{expr:EObjectDecl(newProps), pos:pos}});
                    curProps = newProps; // Reset curProps so children get added properly
                    nodeExt = cloneChild; // Set the cloneChild to be the 'parent' of everything below it
                }
            }

            // If there's a parent element, appendChild
            if(parentVar != null) {
                exprs.push(macro $i{parentVar}.appendChild($i{tempName}));
            } else {
                exprs.push(macro if($i{"parent"} != null) $i{"parent"}.appendChild($i{tempName}));
            }

            // Add children
            for(c in node.nodes) {
                if(Std.is(c, HtmlNodeElement)) {
                    recurseChildren(nodeExt, cast c, tempName, curProps);
                } else if(Std.is(c, HtmlNodeText)) {
                    var nt:HtmlNodeText = cast c;
                    exprs.push(macro $i{tempName}.appendChild(js.Browser.document.createTextNode($v{nt.text})));
                }
            }
            return curProps;
        }
        var pos = Context.makePosition(node.pos);
        var outProps = recurseChildren(node, node.node);
        var outExp:Expr = {expr:EObjectDecl(outProps), pos:pos};
        var retExp:Expr = {expr:EReturn(outExp), pos:pos};
        exprs.push(retExp);
        return macro $b{exprs};
    }

    static function processChunk_HtmlParser(vals:{chunk:String, path:String}):Array<HtmlNodeElementExt> {
        var htmlParsed = HtmlParser.run(vals.chunk);
        var node:HtmlNodeElement = cast htmlParsed.find((n) -> Std.is(n, HtmlNodeElement));
        return processElement_HtmlParser(vals, node);
    }

    static function processElement_HtmlParser(vals:{chunk:String, path:String}, parent:HtmlNodeElement, parentExt:HtmlNodeElementExt = null):Array<HtmlNodeElementExt> {
        var elements:Array<HtmlNodeElementExt> = [];
        if(parent != null) {
            // Clean whitespace
            for(c in [ for(n in parent.nodes) n ]) {
                if(Std.is(c, HtmlNodeText)) {
                    var nt:HtmlNodeText = cast c;
                    if(nt.text.trim().length == 0) nt.remove();
                }
            }
            if(parent.hasAttribute(HExt.attr)) {
                var name = parent.getAttribute(HExt.attr);
                var min = vals.chunk.indexOf('"$name"');
                parentExt = {name:parent.getAttribute(HExt.attr), node:parent, children:[], cloneChildren:[], pos:{file:vals.path, min:min, max:min+name.length}};
                elements.push(parentExt);
            }
            for(attr in [HExt.removeAttr]) {
                if(parent.hasAttribute(attr)) {
                    parent.remove();
                }
            }
            for(child in [ for(c in parent.children) c ]) { // Make a copy of children so if the children are removed the iterator won't fail
                var childElements = processElement_HtmlParser(vals, child, parentExt);
                if(parentExt != null) {
                    for(ce in childElements) {
                        parentExt.children.push(ce);
                        var cloneChild = true;
                        for(attr in [HExt.removeAttr]) if(ce.node.hasAttribute(attr)) cloneChild = false;
                        if(cloneChild) parentExt.cloneChildren.push(ce);
                    }
                } else {
                    for(ce in childElements) elements.push(ce);
                }
            }
            if(parent.hasAttribute(HExt.removeChildrenAttr)) {
                parent.nodes = [];
            }
        }
        return elements;
    }

    static function cleanTypeName(name:String) {
        name = name.replace(" ", "_").replace("-", "_");
        name = name.substr(0, 1).toUpperCase() + name.substr(1);
        return name;
    }

    static function cleanFieldName(name:String) {
        name = name.replace(" ", "_").replace(".", "_").replace("-", "_");
        name = name.substr(0, 1).toLowerCase() + name.substr(1);
        return name;
    }

    static function checkType(type:String):ComplexType {
        return switch(type) {
            // TODO: automate this?
            case "div": TPath({pack:["js","html"], name:"DivElement"});
            case "span": TPath({pack:["js","html"], name:"SpanElement"});
            case "table": TPath({pack:["js","html"], name:"TableElement"});
            case "tr": TPath({pack:["js","html"], name:"TableRowElement"});
            case "td": TPath({pack:["js","html"], name:"TableCellElement"});
            case "input": TPath({pack:["js","html"], name:"InputElement"});
            case "textarea": TPath({pack:["js","html"], name:"TextAreaElement"});
            case _: TPath({pack:["js","html"], name:"Element"});
        }
    }
}

typedef HtmlNodeElementExt = {
    name:String,
    node:HtmlNodeElement, // Raw node template - this may have children removed/etc based on hext-remove attribute
    children:Array<HtmlNodeElementExt>, // Child list of hext named elements
    cloneChildren:Array<HtmlNodeElementExt>, // Child list of hext elements that do not have hext-remove attribute
    pos: {min:Int, max:Int, file:String}
}

#end

