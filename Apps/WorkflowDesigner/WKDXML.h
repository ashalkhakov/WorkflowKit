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
