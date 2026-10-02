#import <Foundation/Foundation.h>

/* What the designer reads and writes of BPMN XML, through NSXML. */

extern NSString * const WKDBpmnNamespace;
extern NSString * const WKDBpmnDINamespace;
extern NSString * const WKDDCNamespace;
extern NSString * const WKDDINamespace;

/* The node is the element of that namespace and local name; local nil:
 * any element of the namespace. */
BOOL WKDIs(NSXMLNode *node, NSString *uri, NSString *local);
NSArray<NSXMLElement *> *WKDChildren(NSXMLElement *element, NSString *uri, NSString *local);
NSXMLElement *WKDChild(NSXMLElement *element, NSString *uri, NSString *local);
/* Every element below, in document order. */
NSArray<NSXMLElement *> *WKDDescendants(NSXMLElement *element, NSString *uri, NSString *local);

/* An unqualified attribute; nil when it has none. */
NSString *WKDAttribute(NSXMLElement *element, NSString *name);
/* Sets it, or with nil removes it. */
void WKDSetAttribute(NSXMLElement *element, NSString *name, NSString *value);
double WKDNumber(NSXMLElement *element, NSString *name);
NSString *WKDFormat(double value);

/* A new element of the namespace, with the prefix the document gives it,
 * declared on the root under the usual one when the document has none. */
NSXMLElement *WKDNewElement(NSXMLDocument *document, NSString *uri, NSString *local);

extern NSString * const WKDCamundaNamespace;
extern NSString * const WKDExtensionNamespace;
extern NSString * const WKDXSINamespace;
/* Camunda's extensions to DMN: camunda:inputVariable. */
extern NSString * const WKDCamundaDmnNamespace;

/* An attribute in a namespace -- camunda:assignee -- by the prefix the
 * document gives the namespace; nil when it has none. */
NSString *WKDQualifiedAttribute(NSXMLDocument *document, NSXMLElement *element, NSString *uri, NSString *local);
/* Sets it, declaring the namespace on the root when the document has not;
 * nil or empty removes it. */
void WKDSetQualifiedAttribute(NSXMLDocument *document, NSXMLElement *element, NSString *uri, NSString *local,
                              NSString *value);
/* The child, made where BPMN's schema puts it when there is none:
 * documentation first, then extensions, incoming, outgoing, the rest, and
 * loop characteristics last. */
NSXMLElement *WKDEnsureChild(NSXMLDocument *document, NSXMLElement *parent, NSString *uri, NSString *local);
/* The child's text; nil when there is no such child. */
NSString *WKDChildText(NSXMLElement *parent, NSString *uri, NSString *local);
/* Sets the child's text, making the child; nil or empty removes it. */
NSXMLElement *WKDSetChildText(NSXMLDocument *document, NSXMLElement *parent, NSString *uri, NSString *local,
                              NSString *text);
/* An element of another document made again in this one, under the parent
 * at the index: each element and qualified attribute -- an xsi:type's value
 * too -- in the prefix this document gives its namespace, declared on its
 * root when it gives none. `from` is the document the element was written
 * in. The element made. */
NSXMLElement *WKDAdoptInto(NSXMLDocument *document, NSXMLElement *element, NSXMLDocument *from, NSXMLElement *parent,
                           NSUInteger index);
/* Every element of the document with the id. */
NSXMLElement *WKDElementWithId(NSXMLDocument *document, NSString *elementId);
/* A copy that writes as the original does -- Apple's copy drops the XML
 * declaration's standalone: what an editor's undo restores. */
NSXMLDocument *WKDCopyDocument(NSXMLDocument *document);
/* Whether the text can be an id: an XML name without a colon. */
BOOL WKDIsName(NSString *name);
