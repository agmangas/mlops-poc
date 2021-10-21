# MLOps Proof of Concept

![Design diagram](diagram.png "Design diagram")

First, create a Python virtual environment and install the requirements for the scripts. It seems that Python 3.8+ is not well supported (some warnings and deprecation notices arised during the initial tests) thus, it is better to stick with Python 3.7.

```
$ virtualenv --python python3.7 ./scripts/.venv
$ source ./scripts/.venv/bin/activate
$ pip install -r ./scripts/requirements.txt
```

The `text_clustering` script is based on scikit-learn's _[clustering text documents using k-means](https://scikit-learn.org/stable/auto_examples/text/plot_document_clustering.html#sphx-glr-auto-examples-text-plot-document-clustering-py)_ example. Running the following command will result in a mini-batch K-means model being trained on the _20 Newsgroups dataset_. The model can then be used to cluster arbitrary documents by the categories of the dataset.

```
$ python ./scripts/text_clustering.py --lsa 100 --output-dir .
```

Save the top terms of each cluster that appear in the command output for later. This is necessary to make sense of the cluster ID that we get as the output of the model.

```
[...]
2021-10-21 07:44:26 fbdb02abf432 root[42] DEBUG Top terms per cluster:
{'Cluster 00': 'uk ac ca article university posting com host nntp virginia',
 'Cluster 01': 'windows file dos files program com ms use window help',
 'Cluster 02': 'com hp article posting nntp host sun att distribution ibm',
 'Cluster 03': 'gatech prism georgia technology institute mike atlanta hrivnak '
               'gtd597a braves',
 'Cluster 04': 'car com cars bike new engine like good just article',
 'Cluster 05': 'israel people jews israeli government jewish arab armenian war '
               'turkish',
 'Cluster 06': 'card video drivers bus monitor mit windows cards vga diamond',
 'Cluster 07': 'key clipper chip encryption com keys escrow government '
               'algorithm security',
 'Cluster 08': 'nasa gov space jpl larc jsc shuttle center gsfc research',
 'Cluster 09': 'cs nyx colorado science university computer dept du utexas '
               'posting',
 'Cluster 10': 'god jesus christian bible people christ christians church '
               'believe faith',
 'Cluster 11': 'don people like just com know think article time good',
 'Cluster 12': 'org mitre article cactus bbs com monitor distribution don '
               'cookson',
 'Cluster 13': 'fbi batf koresh waco com people government children atf '
               'compound',
 'Cluster 14': 'drive scsi ide disk drives hard controller floppy hd com',
 'Cluster 15': 'game games espn baseball hockey columbia university cc gld '
               'team',
 'Cluster 16': 'netcom cleveland cwru freenet com 408 reserve ins western 9760',
 'Cluster 17': 'uiuc cso illinois urbana uxa university news cobb article '
               'irvine',
 'Cluster 18': 'university thanks mail posting host nntp know help sale state',
 'Cluster 19': 'team ca year game players hockey season win play nhl'}
```

Two new files will appear in the current directory:

- `model.joblib` is the serialized version of the text clustering model.
- `transformer.joblib` is the serialized version of the pre-processing pipeline, including a TF-IDF vectorization step and a latent semantic analysis dimensionality reduction step.

The next step is to prepare the development environment; this is a fairly complicated process that mainly consists of deploying [KServe](https://kserve.github.io/website/) and [MinIO](https://min.io/) on a Kubernetes cluster. Thankfully, we can leverage [Vagrant](https://www.vagrantup.com/) and the `Vagrantfile` in the root of this repository to automate the creation of an Ubuntu-based virtual machine for testing purposes.

> Please note that the VM requires 12GB of memory and 5 CPU cores.

The following command will initialize an Ubuntu VM and run all the provisioning scripts to:

- Install Docker.
- Install [Kind](https://kind.sigs.k8s.io/) and create a Kubernetes cluster.
- Install Kubectl and Helm.
- Deploy a MetalLB load balancer.
- Install KServe.
- Install and configure MinIO, including a minimal MinIO tenant.
- Deploy a HAProxy reverse proxy to enable external access to KServe's ingress gateway.

It will take a while to finish (approximately 10 minutes).

```
$ vagrant up
```

Then, you can run `vagrant ssh` to connect to the VM.

For example, you may check from inside the VM that MinIO was successfully deployed by verifying that there are two _NodePort_ services in the `tenant-tiny` namespace (MinIO Server and MinIO Console):

```
vagrant@mlops-poc:~$ kubectl get svc -n tenant-tiny
NAME                             TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
console-service                  NodePort    10.96.178.66    <none>        9090:30200/TCP   5m57s
minio                            ClusterIP   10.96.50.91     <none>        80/TCP           5m29s
minio-service                    NodePort    10.96.145.20    <none>        9000:30100/TCP   5m57s
storage-tiny-console             ClusterIP   10.96.174.246   <none>        9090/TCP         5m28s
storage-tiny-hl                  ClusterIP   None            <none>        9000/TCP         5m28s
storage-tiny-log-hl-svc          ClusterIP   None            <none>        5432/TCP         4m50s
storage-tiny-log-search-api      ClusterIP   10.96.69.171    <none>        8080/TCP         4m50s
storage-tiny-prometheus-hl-svc   ClusterIP   None            <none>        9090/TCP         3m9s
```

As you can see above, _MinIO Server_ is available on port **30100**, while _MinIO Console_ is available on port **30200**. These services will also be available from _outside_ the VM due to the NAT configuration that is defined in the `Vagrantfile`. The default root user is `minio` with password `minio123`:

> `mc` is the [MinIO command line client](https://docs.min.io/docs/minio-client-quickstart-guide.html)

```
$ mc alias set tiny http://localhost:30100 minio minio123 && mc --debug tree tiny
Added `tiny` successfully.
mc: <DEBUG> GET / HTTP/1.1
Host: localhost:30100
User-Agent: MinIO (darwin; amd64) minio-go/v7.0.15 mc/RELEASE.2021-09-23T05-44-03Z
Authorization: AWS4-HMAC-SHA256 Credential=minio/20211020/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature=**REDACTED**
X-Amz-Content-Sha256: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
X-Amz-Date: 20211020T151408Z
Accept-Encoding: gzip

mc: <DEBUG> HTTP/1.1 200 OK
Content-Length: 275
Accept-Ranges: bytes
Content-Security-Policy: block-all-mixed-content
Content-Type: application/xml
Date: Wed, 20 Oct 2021 15:14:07 GMT
Server: MinIO
Strict-Transport-Security: max-age=31536000; includeSubDomains
Vary: Origin
Vary: Accept-Encoding
X-Amz-Request-Id: 16AFC5F54E9B4BE2
X-Content-Type-Options: nosniff
X-Xss-Protection: 1; mode=block

mc: <DEBUG> Response Time:  3.774223ms
```

In KServe, an `InferenceService` is the entity that encapsulates the components that are required to deploy an AI model to production; for example, a model storage initializer, a _predictor_ service, and a _transformer_ service. More specifically, to deploy an `InferenceService` we need to:

- Upload the `model.joblib` and `transformer.joblib` files to the object storage service.
- Create the `Secret` and `ServiceAccount` resources required by KServe to connect to MinIO.
- Create the `InferenceService` resource, including the `transformer` pre-processing step.

These steps can be automated with the `deploy_service.py` script, which takes the following arguments:

- `--namespace`: Kubernetes namespace where the resources will be created.
- `--model-path`: Path to the serialized model (joblib format).
- `--model-name`: Descriptive name of the inference service.
- ` --transformer-path`: Path to the serialized pre-processing transformer (joblib format).
- `--transformer-image`: Name of the image that will be utilized to run containers for the [transformer pre-processing step](https://kserve.github.io/website/modelserving/v1beta1/transformer/torchserve_image_transformer/).

In this particular text clustering example, the `--transformer-image` can be built from `transformer.Dockerfile`, which basically installs the package requirements and copies the `transformer.py` script to a Python 3.7 image:

> Please note that the following command pushes the image to Docker's registry, and will therefore fail if you don't run `docker login` to log in first.

```
vagrant@mlops-poc:~$ docker build -t agmangas/sklearn-transformer:latest -f /vagrant/transformer.Dockerfile /vagrant/ && docker push agmangas/sklearn-transformer:latest
```

Image [agmangas/sklearn-transformer](https://hub.docker.com/r/agmangas/sklearn-transformer) should be publicly available, thus we can use it instead of having to upload our own image to an externally accessible registry.

```
vagrant@mlops-poc:~$ /home/vagrant/venv/bin/python /vagrant/scripts/deploy_service.py --log-level INFO --model-path /vagrant/model.joblib --model-name textclustering --namespace kserve-textclustering --transformer-path /vagrant/transformer.joblib --transformer-image agmangas/sklearn-transformer:latest
2021-10-20 11:32:57 mlops-poc root[59588] INFO Using model textclustering from /vagrant/model.joblib
2021-10-20 11:32:57 mlops-poc root[59588] INFO Created bucket: s3.Bucket(name='textclustering')
2021-10-20 11:32:57 mlops-poc root[59588] INFO Uploaded model: /vagrant/model.joblib
2021-10-20 11:32:57 mlops-poc root[59588] INFO Uploaded transformer: /vagrant/transformer.joblib
2021-10-20 11:32:57 mlops-poc sh.command[59588] INFO <Command '/usr/local/bin/kubectl create namespace kserve-textclustering', pid 59595>: process started
2021-10-20 11:32:57 mlops-poc sh.command[59588] INFO <Command '/usr/local/bin/kubectl apply -n kserve-textclustering -f /tmp/tmpur69q815/s3-secrets.yaml', pid 59607>: process started
2021-10-20 11:32:58 mlops-poc sh.command[59588] INFO <Command '/usr/local/bin/kubectl apply -n kserve-textclustering -f /tmp/tmpplwcgz2g/inference-service.yaml', pid 59620>: process started
```

Below you can see the details of the `Secret`, `ServiceAccount` and `InferenceService` Kubernetes resources created by the script.

Unlike in the case of the _transformer_, where we need to build an ad-hoc image, there is already a Scikit Learn _predictor_ server built into KServe. To avoid any unexpected issues when using the built-in servers, the models should be developed using the [same versions as Kserve](https://github.com/kserve/kserve/blob/v0.7.0/python/sklearnserver/setup.py).

```
apiVersion: v1
kind: Secret
metadata:
  annotations:
    serving.kserve.io/s3-endpoint: minio-service.tenant-tiny:9000
    serving.kserve.io/s3-region: eu-west-1
    serving.kserve.io/s3-useanoncredential: 'false'
    serving.kserve.io/s3-usehttps: '0'
  name: s3creds
stringData:
  AWS_ACCESS_KEY_ID: minio
  AWS_SECRET_ACCESS_KEY: minio123
type: Opaque
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sa
secrets:
- name: s3creds
```

```
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: textclustering
spec:
  predictor:
    serviceAccountName: sa
    sklearn:
      storageUri: s3://textclustering
  transformer:
    containers:
    - env:
      - name: STORAGE_URI
        value: s3://textclustering/transformer.joblib
      image: agmangas/sklearn-transformer:latest
      name: textclustering-transformer
    serviceAccountName: sa
```

Once deployed to Kubernetes, the `InferenceService` should be ready after a few minutes at most:

```
vagrant@mlops-poc:~$ kubectl get inferenceservices -n kserve-textclustering
NAME             URL                                                       READY   PREV   LATEST   PREVROLLEDOUTREVISION   LATESTREADYREVISION                      AGE
textclustering   http://textclustering.kserve-textclustering.example.com   True           100                              textclustering-predictor-default-00001   29m

vagrant@mlops-poc:~$ kubectl get deployments -n kserve-textclustering
NAME                                                  READY   UP-TO-DATE   AVAILABLE   AGE
textclustering-predictor-default-00001-deployment     1/1     1            1           29m
textclustering-transformer-default-00001-deployment   1/1     1            1           29m```
```

If any problems arise during this deployment process, you can get further information from the `Pod` logs and the `Revisions` for debugging purposes:

```
vagrant@mlops-poc:~$ kubectl get revisions -n kserve-textclustering
NAME                                       CONFIG NAME                          K8S SERVICE NAME                           GENERATION   READY   REASON
textclustering-predictor-default-00001     textclustering-predictor-default     textclustering-predictor-default-00001     1            True
textclustering-transformer-default-00001   textclustering-transformer-default   textclustering-transformer-default-00001   1            True

vagrant@mlops-poc:~$ kubectl describe revision/textclustering-transformer-default-00001 -n kserve-textclustering
[...]
Events:
  Type     Reason         Age                From                 Message
  ----     ------         ----               ----                 -------
  Warning  InternalError  30m (x2 over 32m)  revision-controller  failed to update deployment "textclustering-transformer-default-00001-deployment": Operation cannot be fulfilled on deployments.apps "textclustering-transformer-default-00001-deployment": the object has been modified; please apply your changes to the latest version and try again
[...]

vagrant@mlops-poc:~$ kubectl get pods -n kserve-textclustering
NAME                                                              READY   STATUS    RESTARTS   AGE
textclustering-predictor-default-00001-deployment-6f5d65f99qrwr   2/2     Running   0          37m
textclustering-transformer-default-00001-deployment-6ddcbbjdvpj   2/2     Running   0          37m

vagrant@mlops-poc:~$ kubectl logs -n kserve-textclustering textclustering-predictor-default-00001-deployment-6f5d65f99qrwr --all-containers
[...]
[I 211021 08:10:36 credentials:1102] Found credentials in environment variables.
[I 211021 08:10:36 storage:85] Successfully copied s3://textclustering to /mnt/models
[...]
```

At this point, the `textclustering` _inference service_ is finally ready to serve requests to the text clustering model. There is an example request below that uses the [V1 Data Plane protocol](https://kserve.github.io/website/modelserving/data_plane/) interface. Note how the raw document goes through the _transformer_ for feature extraction before being fed to the clustering model.

```
$ curl -v \
-H "Host: textclustering.kserve-textclustering.example.com" \
http://localhost:30300/v1/models/textclustering:predict \
-d '{"instances":[["Incubator lean startup creative alpha user experience entrepreneur product management crowdfunding. Alpha first mover advantage seed money android customer."]]}'
*   Trying 127.0.0.1:30300...
* TCP_NODELAY set
* Connected to localhost (127.0.0.1) port 30300 (#0)
> POST /v1/models/textclustering:predict HTTP/1.1
> Host: textclustering.kserve-textclustering.example.com
> User-Agent: curl/7.68.0
> Accept: */*
> Content-Length: 176
> Content-Type: application/x-www-form-urlencoded
>
* upload completely sent off: 176 out of 176 bytes
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 OK
< content-length: 20
< content-type: application/json; charset=UTF-8
< date: Thu, 21 Oct 2021 08:14:20 GMT
< server: istio-envoy
< x-envoy-upstream-service-time: 14
<
* Connection #0 to host localhost left intact
{"predictions": [0]}
```
