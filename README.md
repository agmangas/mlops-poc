# MLOps Examples and Proof of Concepts

## KFServing

> Tested with KFServing version `v0.6.1` on Minikube OSX.

First, [install Minikube](https://minikube.sigs.k8s.io/docs/start/) if necessary. Make sure to update the Docker Desktop Kubernetes context to _minikube_.

Note that the [quick install script](https://github.com/kubeflow/kfserving/tree/v0.6.1#quick-install-on-your-local-machine) of KFServing installs Istio 1.9.0. However, [Istio 1.9.0 only supports Kubernetes from 1.17 to 1.20](https://istio.io/latest/docs/releases/supported-releases/#support-status-of-istio-releases). Therefore, use a compatible Kubernetes version when creating the minikube cluster:

```
$ minikube start --memory=11980 --cpus=4 --kubernetes-version=v1.20.2
```

Now we can clone the [KFServing repo](https://github.com/kubeflow/kfserving/tree/v0.6.1) and run the quick install script:

```
$ ./hack/quick_install.sh
[...]

Begin the Istio pre-installation check by running:
	 istioctl x precheck

Need more information? Visit https://istio.io/latest/docs/setup/install/
namespace/istio-system created
✔ Istio core installed
✔ Istiod installed
✔ Ingress gateways installed

[...]

validatingwebhookconfiguration.admissionregistration.k8s.io/trainedmodel.serving.kubeflow.org configured
```

We can now [deploy a _KFServing inference service_ for testing](https://github.com/kubeflow/kfserving/tree/v0.6.1#create-kfserving-test-inference-service):

```
$ export API_VERSION=v1beta1
$ kubectl create namespace kfserving-test
namespace/kfserving-test created
$ kubectl apply -f docs/samples/${API_VERSION}/sklearn/v1/sklearn.yaml -n kfserving-test
inferenceservice.serving.kubeflow.org/sklearn-iris created
```

Wait for this particular instance of `inferenceservice.serving.kubeflow.org` to be ready:

```
$ kubectl rollout status deployment/sklearn-iris-predictor-default-00001-deployment -n kfserving-test
Waiting for deployment "sklearn-iris-predictor-default-00001-deployment" rollout to finish: 0 of 1 updated replicas are available...
deployment "sklearn-iris-predictor-default-00001-deployment" successfully rolled out
$ kubectl get inferenceservices sklearn-iris -n kfserving-test
NAME           URL                                              READY   PREV   LATEST   PREVROLLEDOUTREVISION   LATESTREADYREVISION                    AGE
sklearn-iris   http://sklearn-iris.kfserving-test.example.com   True           100                              sklearn-iris-predictor-default-00001   119s
```

Run `minikube tunnel` in another terminal to enable the load balancer. You can [verify that Istio is using a Kubernetes-provided load balancer](https://istio.io/latest/docs/tasks/traffic-management/ingress/ingress-control/#determining-the-ingress-ip-and-ports) with:

```
$ kubectl get svc istio-ingressgateway -n istio-system
NAME                   TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)                                                                      AGE
istio-ingressgateway   LoadBalancer   10.101.65.241   127.0.0.1     15021:32424/TCP,80:30214/TCP,443:31189/TCP,15012:32029/TCP,15443:32543/TCP   44m
```

Finally, we can send a request to the inference service:

```
$ export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
$ export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
$ export SERVICE_HOSTNAME=$(kubectl get inferenceservice sklearn-iris -n kfserving-test -o jsonpath='{.status.url}' | cut -d "/" -f 3)
$ curl -v -H "Host: ${SERVICE_HOSTNAME}" http://${INGRESS_HOST}:${INGRESS_PORT}/v1/models/sklearn-iris:predict -d @./docs/samples/${API_VERSION}/sklearn/v1/iris-input.json
*   Trying 127.0.0.1...
* TCP_NODELAY set
* Connected to 127.0.0.1 (127.0.0.1) port 80 (#0)
> POST /v1/models/sklearn-iris:predict HTTP/1.1
> Host: sklearn-iris.kfserving-test.example.com
> User-Agent: curl/7.64.1
> Accept: */*
> Content-Length: 76
> Content-Type: application/x-www-form-urlencoded
>
* upload completely sent off: 76 out of 76 bytes
< HTTP/1.1 200 OK
< content-length: 23
< content-type: application/json; charset=UTF-8
< date: Fri, 17 Sep 2021 12:42:54 GMT
< server: istio-envoy
< x-envoy-upstream-service-time: 4
<
* Connection #0 to host 127.0.0.1 left intact
{"predictions": [1, 1]}* Closing connection 0
```

Also, the [Models UI](https://www.kubeflow.org/docs/components/kfserving/webapp/) web app will also be available through the Istio Ingress Gateway:

```
$ echo http://$INGRESS_HOST:$INGRESS_PORT/models/
http://127.0.0.1:80/models/
```