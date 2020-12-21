---
layout: post
title: Setting up Resilience4j Circuit Breaker for Grpc Java Client
author: alicanhaman
categories: [grpc, resilience4j]
tags: [grpc, resilience4j, spring boot]
---

This article explains how to set up [Resilience4j](https://github.com/resilience4j/resilience4j) circuit breaker to work with a grpc client set up with [grpc-spring-boot-starter](https://github.com/yidongnan/grpc-spring-boot-starter). Normally, resilience4j is built to handle restful requests easily, but when it comes to grpc is [falls short](https://github.com/resilience4j/resilience4j/issues/1067). There is an open PR in the resilience4j repository, but it seems to have been left to rot.

First, let us briefly mention our stack: 

- **Resilience4j** is a lightweight fault tolerance library inspired by [Netflix Hystrix](https://github.com/Netflix/Hystrix), but designed for Java 8 and functional programming. Lightweight, because the library only uses Vavr, which does not have any other external library dependencies. Netflix Hystrix, in contrast, has a compile dependency to Archaius which has many more external library dependencies such as Guava and Apache Commons Configuration. Since Hytrix has been moved to maintenance about 2 years ago, this library is deemed as a good alternative.
- **gRPC** is a modern open source high performance RPC framework that can run in any environment. It can efficiently connect services in and across data centers with pluggable support for load balancing, tracing, health checking and authentication.

# Proto project

## Dependencies

To get grpc working, we need a protofile definition and generate classes from there.
For that, we need to add some grpc dependencies.

``` xml
    <dependencies>
        <dependency>
            <groupId>io.grpc</groupId>
            <artifactId>grpc-stub</artifactId>
            <version>1.34.0</version>
        </dependency>
        <dependency>
            <groupId>io.grpc</groupId>
            <artifactId>grpc-protobuf</artifactId>
            <version>1.34.0</version>
        </dependency>
        <dependency>
            <!-- Java 9+ compatibility -->
            <groupId>javax.annotation</groupId>
            <artifactId>javax.annotation-api</artifactId>
        </dependency>
    </dependencies>
```

## Using Maven Plugin
And we can use a plugin to generate the code automatically with maven

``` xml
<build>
  <extensions>
    <extension>
      <groupId>kr.motd.maven</groupId>
      <artifactId>os-maven-plugin</artifactId>
      <version>1.6.1</version>
    </extension>
  </extensions>
  <plugins>
    <plugin>
      <groupId>org.xolstice.maven.plugins</groupId>
      <artifactId>protobuf-maven-plugin</artifactId>
      <version>0.6.1</version>
      <configuration>
        <protocArtifact>
          com.google.protobuf:protoc:3.3.0:exe:${os.detected.classifier}
        </protocArtifact>
        <pluginId>grpc-java</pluginId>
        <pluginArtifact>
          io.grpc:protoc-gen-grpc-java:1.4.0:exe:${os.detected.classifier}
        </pluginArtifact>
      </configuration>
      <executions>
        <execution>
          <goals>
            <goal>compile</goal>
            <goal>compile-custom</goal>
          </goals>
        </execution>
      </executions>
    </plugin>
  </plugins>
</build>
```

## Proto File

Here is how a proto file for a service that gets a HelloRequest and returns a custom greeting would look like.

``` protobuf
syntax = "proto3";

option java_multiple_files = true;
option java_package = "com.deepnetwork.grpc";
option java_outer_classname = "HelloProto";

// Hello Service definition
service HelloService {
    rpc hello(HelloRequest) returns (HelloResponse);
}

message HelloRequest {
    string firstName = 1;
    string lastName = 2;
}

message HelloResponse {
    string greeting = 1;
}
```

# Grpc Client
## Dependencies

We have to add our proto project, resilience4j, and [grpc-client](https://github.com/yidongnan/grpc-spring-boot-starter)

``` xml
<dependencies>
  <dependency>
      <groupId>net.devh</groupId>
      <artifactId>grpc-client-spring-boot-starter</artifactId>
      <version>2.10.1.RELEASE</version>
  </dependency>
  <!-- basically your grpc proto project -->
  <dependency>
      <groupId>com.deepnetwork</groupId>
      <artifactId>hello-service-grpc</artifactId>
      <version>${project.version}</version>
  </dependency>
  <dependency>
      <groupId>io.github.resilience4j</groupId>
      <artifactId>resilience4j-spring-boot2</artifactId>
      <version>1.6.1</version>
  </dependency>
</dependencies>
```

## Configuration
You can configure resilience4j-spring-boot2 with `application.yml` file in resources folder. 
More examples can be found in [resilience4j user guide](https://resilience4j.readme.io/docs/getting-started-3)

``` yml
resilience4j.circuitbreaker:
  configs:
    default:
      registerHealthIndicator: true
      slidingWindowSize: 10
      minimumNumberOfCalls: 5
      permittedNumberOfCallsInHalfOpenState: 3
      automaticTransitionFromOpenToHalfOpenEnabled: true
      waitDurationInOpenState: 5s
      failureRateThreshold: 50
      eventConsumerBufferSize: 10
      recordExceptions:
        - io.grpc.StatusRuntimeException
  instances:
    helloService:
      baseConfig: default
```

## Spring boot service that makes grpc client call

With the resilience4j-spring-boot2 library, we can add circuitbreaker to a service call by using `@CircuitBreaker(name = "helloService")` annotation. Here is how our method looks like;

``` java
@Service
public class HelloServiceImpl implements HelloService {

    @GrpcClient("hello-service")
    private HelloServiceGrpc.HelloServiceBlockingStub helloServiceBlockingStub;
    private static final String HELLO_SERVICE = "helloService";

    @CircuitBreaker(name = HELLO_SERVICE)
    @Override
    public String sayHello(String firstName, String lastName) {
        HelloRequest helloRequest = helloRequest.newBuilder()
                .setFirtName(firstName)
                .setLastName(lastName)
                .build();
        HelloResponse helloResponse = helloServiceBlockingStub.hello(helloRequest);
        return helloResponse.getGreeting();
    }
```

## Intercepting calls and customizing circuitbreaker

The ClientInterceptor will intercept every single call to the client. If the CircuitBreaker is in closed or half-closed state call will be permitted and the grpc request can continue.
<p>
It will also add a custom listener to every single grpc call that has gone through checking the status of the grpc response. If it is a server side error it will be judged as circuitBreaker error, otherwise, it will be judged as a success. Therefore helping circuitBreaker decide when it needs to close.

``` java
public final class CircuitBreakerClientInterceptor implements ClientInterceptor {

    private final CircuitBreaker circuitBreaker;

    public CircuitBreakerClientInterceptor(CircuitBreaker circuitBreaker) {
        super();
        this.circuitBreaker = circuitBreaker;
    }

    @Override
    public <ReqT, RespT> ClientCall<ReqT, RespT> interceptCall(
            MethodDescriptor<ReqT, RespT> method, CallOptions callOptions, Channel next) {
        return new CheckedForwardingClientCall(next.newCall(method, callOptions)) {

            @Override
            protected void checkedStart(ClientCall.Listener responseListener, io.grpc.Metadata headers) {
                if (CircuitBreakerUtil.isCallPermitted(circuitBreaker))
                    this.delegate().start(new CircuitBreakerClientInterceptor.Listener(responseListener, System.nanoTime()), headers);
            }
        };
    }

    private final class Listener extends SimpleForwardingClientCallListener {
        private final long startedAt;
        // Server errors are taken from table in https://cloud.google.com/apis/design/errors
        private final Set<Status.Code> serverErrorStatusSet = Set.of(
                Status.Code.DATA_LOSS,
                Status.Code.UNKNOWN,
                Status.Code.INTERNAL,
                Status.Code.UNIMPLEMENTED,
                Status.Code.UNAVAILABLE,
                Status.Code.DEADLINE_EXCEEDED
        );

        public Listener(io.grpc.ClientCall.Listener delegate, long startedAt) {
            super(delegate);
            this.startedAt = startedAt;
        }

        @Override
        public void onClose(Status status, io.grpc.Metadata trailers) {
            long elapsed = System.nanoTime() - startedAt;
            // If the status code is not a server error status code add a success to circuitBreaker
            if (!serverErrorStatusSet.contains(status.getCode())) {
                CircuitBreakerClientInterceptor.this.circuitBreaker.onSuccess(elapsed, TimeUnit.NANOSECONDS);
            } else {
                CircuitBreakerClientInterceptor.this.circuitBreaker.onError(elapsed, TimeUnit.NANOSECONDS,
                        new StatusRuntimeException(status, trailers));
            }

            super.onClose(status, trailers);
        }
    }
}
```

## Configuring the grpc client for interceptor

We will also need to make the grpc client use our interceptor, there are some examples for that in [grpc-spring-boot-starter/examples](https://github.com/yidongnan/grpc-spring-boot-starter/tree/master/examples)

It will basically look like this
``` java
@Configuration(proxyBeanMethods = false)
public class GlobalClientInterceptorConfiguration {

    private static final String HELLO_SERVICE = "helloService";
    protected final CircuitBreakerRegistry circuitBreakerRegistry;

    public GlobalClientInterceptorConfiguration(CircuitBreakerRegistry circuitBreakerRegistry) {
        this.circuitBreakerRegistry = circuitBreakerRegistry;
    }

    @GrpcGlobalClientInterceptor
    ClientInterceptor circuitBreakerClientInterceptor() {
        return new CircuitBreakerClientInterceptor(circuitBreakerRegistry.circuitBreaker(HELLO_SERVICE));
    }
}
```

## Final Words

Please don't hesitate to [connect](https://www.linkedin.com/in/alican-haman/) / contact via alican.haman[at]deepnetwork.com.

## Further reading

You can check out what circuit breaker is and how it works from [here](https://buttondown.email/computer-napkins/archive/napkin-problem-11-circuit-breakers/)

If you are interested in how resilience4j works check out the [Getting Started Doc](https://resilience4j.readme.io/docs/getting-started-3) for resilience4j.

I would also recommend [this talk](https://www.youtube.com/watch?v=KosSsZEqS-k) by one of the contributors of the library. It explains in detail all the fault tolerance concepts in the library.

# References
- Resilience4j introduction [[1]]
- About gRPC [[2]]
- Baeldung Introduction to gRPC [[3]]
- Grpc examples [[4]]
- Example kotlin code for interceptor [[5]]

[1]:https://github.com/resilience4j/resilience4j#1-introduction
[2]:https://grpc.io/about/
[3]:https://www.baeldung.com/grpc-introduction
[4]:https://github.com/yidongnan/grpc-spring-boot-starter/tree/master/examples
[5]:https://gist.github.com/eungju/226274b3dacb3203de3514bcf1c54505
